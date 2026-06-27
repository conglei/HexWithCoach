//
//  CoachService.swift
//  HexIOS
//
//  RC-2 wiring: the orchestration that turns the dictation corpus into Review-feed
//  cards. Runs the corpus-stateful pipeline (CE-3) over a *bounded* slice of the
//  un-analyzed backlog — NOT once per utterance — on activation/refresh, persists
//  the curated cards (CoachCardEntity), updates the LearnerProfile, and tracks a
//  running BYOK cost estimate. Text-only for cost; fluency signals still use the
//  audio's real duration when it's on disk.
//

import AVFoundation
import Foundation
import HexCore
import Observation
import SwiftData

@MainActor
@Observable
final class CoachService {
    private let modelContext: ModelContext
    private let preferences: CoachPreferences

    private(set) var isAnalyzing = false
    var errorMessage: String?

    /// Accumulated estimated BYOK spend (USD), persisted in the App Group so the
    /// user can see it in Settings and isn't surprised.
    private(set) var totalCostUSD: Double

    /// The monthly cost cap (CE-5). Persisted in the App Group; setting it writes
    /// through so the next run honors it immediately.
    var budget: CoachBudget {
        didSet {
            if let cap = budget.monthlyCapUSD {
                defaults.set(cap, forKey: Self.capKey)
            } else {
                defaults.removeObject(forKey: Self.capKey)
            }
        }
    }

    /// Set when a run stopped because this month's spend hit the cap — surfaced
    /// in Settings so the user knows why coaching paused.
    private(set) var budgetReached = false

    /// Cost/volume bounds per run (the part that diverges from the macOS
    /// per-recording coach).
    var perRunTranscriptLimit = 20
    var perRunCardLimit = 7

    private let defaults = UserDefaults(suiteName: HexAppGroup.identifier) ?? .standard
    @ObservationIgnored private static let costKey = "hex.coach.totalCostUSD"
    @ObservationIgnored private static let capKey = "hex.coach.monthlyCapUSD"
    @ObservationIgnored private static let spendKeyPrefix = "hex.coach.spend."

    init(modelContext: ModelContext, preferences: CoachPreferences) {
        self.modelContext = modelContext
        self.preferences = preferences
        totalCostUSD = defaults.double(forKey: Self.costKey)
        // A stored value of 0 (the UserDefaults default for a missing key) means
        // "uncapped"; only treat a positive stored value as a real cap.
        let storedCap = defaults.double(forKey: Self.capKey)
        budget = CoachBudget(monthlyCapUSD: storedCap > 0 ? storedCap : nil)
    }

    /// This month's estimated spend (USD), read from the per-month bucket.
    var spentThisMonthUSD: Double {
        defaults.double(forKey: Self.spendKey(for: Date()))
    }

    private static func spendKey(for date: Date) -> String {
        spendKeyPrefix + CoachBudget.monthKey(for: date)
    }

    /// Add an increment of cost to the current month's bucket and the lifetime
    /// total, persisting both so the cap takes effect within a run.
    private func recordSpend(_ amount: Double) {
        guard amount > 0 else { return }
        let key = Self.spendKey(for: Date())
        defaults.set(defaults.double(forKey: key) + amount, forKey: key)
        totalCostUSD += amount
        defaults.set(totalCostUSD, forKey: Self.costKey)
    }

    private var profileStore: LearnerProfileStore {
        let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HexAppGroup.identifier)?
            .appendingPathComponent("Coach", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
        return LearnerProfileStore(url: dir.appendingPathComponent("profile.json"))
    }

    /// Count of transcripts not yet analyzed — the activation bait + refresh badge.
    func backlogCount() -> Int {
        let descriptor = FetchDescriptor<TranscriptEntry>(predicate: #Predicate { $0.coachAnalyzedAt == nil })
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Analyze a bounded slice of the un-analyzed backlog and produce cards.
    /// No-op unless the Coach is opted in with a key.
    func analyzeBacklog() async {
        guard preferences.isReady, !isAnalyzing else { return }
        guard let apiKey = CoachKeychain.read(CoachKeychain.geminiAPIKeyAccount), !apiKey.isEmpty else { return }

        // Don't even start a run once this month's spend has hit the cap (CE-5).
        guard budget.canAnalyze(spentThisMonth: spentThisMonthUSD) else {
            budgetReached = true
            return
        }
        budgetReached = false

        isAnalyzing = true
        defer { isAnalyzing = false }

        var descriptor = FetchDescriptor<TranscriptEntry>(
            predicate: #Predicate { $0.coachAnalyzedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = perRunTranscriptLimit
        guard let batch = try? modelContext.fetch(descriptor), !batch.isEmpty else { return }

        let pipeline = CoachPipeline(llm: GeminiCoachLLM(apiKey: apiKey))
        var profile = profileStore.load()
        let now = Date()
        let masteredBefore = Set(profile.patterns.filter { $0.status == .mastered }.map(\.key))

        var allInsights: [CoachInsight] = []

        for entry in batch {
            let words = entry.text.split { $0.isWhitespace }.count
            let durationSec = duration(forAudio: entry.audioFilename, fallbackWordCount: words)

            // Skip trivially short dictations — too little to coach on, and not
            // worth the spend. Mark them analyzed so they roll out of the backlog.
            if durationSec < Self.minDurationSec {
                entry.coachAnalyzedAt = now
                continue
            }

            // Send the audio too (multimodal lens) so the model can actually hear
            // pronunciation/prosody, not just read the transcript.
            let audioClip = audio(for: entry.audioFilename)
            let input = CoachTranscriptInput(
                id: entry.id, text: entry.text, durationSec: durationSec, audio: audioClip
            )
            do {
                let analysis = try await pipeline.analyze(input, profile: &profile, at: now)
                allInsights.append(contentsOf: analysis.insights)
                let cost = Self.estimatedCost(chars: entry.text.count, audioSec: audioClip == nil ? 0 : durationSec)
                recordSpend(cost)
                entry.coachAnalyzedAt = now
            } catch {
                // Stop on the first hard error (e.g. a bad key) so we don't keep
                // spending; surface it to the feed.
                errorMessage = error.localizedDescription
                break
            }

            // Enforce the monthly cap mid-run: once this month's spend reaches it,
            // stop so the cap is a real ceiling, not just a per-run hint.
            if !budget.canAnalyze(spentThisMonth: spentThisMonthUSD) {
                budgetReached = true
                break
            }
        }

        let wins = profile.patterns.filter { $0.status == .mastered && !masteredBefore.contains($0.key) }
        let merged = CoachAnalysis(insights: allInsights, focuses: [], signals: FluencySignals())
        let cards = CoachCardCurator.curate(analysis: merged, wins: wins, profile: profile, now: now, limit: perRunCardLimit)
        for card in cards { modelContext.insert(CoachCardEntity(card: card)) }

        try? profileStore.save(profile)
        try? modelContext.save()
    }

    // MARK: - Helpers

    /// Below this, a dictation is too short to coach on — skip it.
    private static let minDurationSec: Double = 10

    /// Real audio duration when the file is on disk; otherwise a ~150 wpm estimate.
    private func duration(forAudio filename: String?, fallbackWordCount: Int) -> Double {
        if let url = AudioStore.url(for: filename),
           let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 {
            return player.duration
        }
        return max(1, Double(fallbackWordCount) / 150 * 60)
    }

    /// Load a transcript's retained audio for the multimodal lens (nil if none).
    private func audio(for filename: String?) -> CoachAudio? {
        guard let url = AudioStore.url(for: filename), let data = try? Data(contentsOf: url) else { return nil }
        return CoachAudio(data: data, mimeType: "audio/wav")
    }

    /// Rough per-transcript cost: cheap extract (with audio, ~32 tok/s) + stronger
    /// text-only critic. Precise token accounting is CE-5; this keeps the running
    /// estimate honest enough to not surprise.
    private static func estimatedCost(chars: Int, audioSec: Double) -> Double {
        let audioTokens = Int(audioSec * 32)
        let extractPrompt = max(200, chars / 4 + 400 + audioTokens)
        let criticPrompt = max(200, chars / 4 + 400)
        let output = 250
        return CoachCostEstimator.usd(promptTokens: extractPrompt, outputTokens: output, model: GeminiClient.Model.flashLite)
            + CoachCostEstimator.usd(promptTokens: criticPrompt, outputTokens: output, model: GeminiClient.Model.flash)
    }
}
