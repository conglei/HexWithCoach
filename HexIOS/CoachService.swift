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

    /// Cost/volume bounds per run (the part that diverges from the macOS
    /// per-recording coach).
    var perRunTranscriptLimit = 20
    var perRunCardLimit = 7

    private let defaults = UserDefaults(suiteName: HexAppGroup.identifier) ?? .standard
    @ObservationIgnored private static let costKey = "hex.coach.totalCostUSD"

    init(modelContext: ModelContext, preferences: CoachPreferences) {
        self.modelContext = modelContext
        self.preferences = preferences
        totalCostUSD = defaults.double(forKey: Self.costKey)
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
        var runCost = 0.0

        for entry in batch {
            let words = entry.text.split { $0.isWhitespace }.count
            let input = CoachTranscriptInput(
                id: entry.id, text: entry.text,
                durationSec: duration(forAudio: entry.audioFilename, fallbackWordCount: words)
            )
            do {
                let analysis = try await pipeline.analyze(input, profile: &profile, at: now)
                allInsights.append(contentsOf: analysis.insights)
                runCost += Self.estimatedCost(forTranscriptChars: entry.text.count)
                entry.coachAnalyzedAt = now
            } catch {
                // Stop on the first hard error (e.g. a bad key) so we don't keep
                // spending; surface it to the feed.
                errorMessage = error.localizedDescription
                break
            }
        }

        let wins = profile.patterns.filter { $0.status == .mastered && !masteredBefore.contains($0.key) }
        let merged = CoachAnalysis(insights: allInsights, focuses: [], signals: FluencySignals())
        let cards = CoachCardCurator.curate(analysis: merged, wins: wins, profile: profile, now: now, limit: perRunCardLimit)
        for card in cards { modelContext.insert(CoachCardEntity(card: card)) }

        try? profileStore.save(profile)
        try? modelContext.save()
        totalCostUSD += runCost
        defaults.set(totalCostUSD, forKey: Self.costKey)
    }

    // MARK: - Helpers

    /// Real audio duration when the file is on disk; otherwise a ~150 wpm estimate.
    private func duration(forAudio filename: String?, fallbackWordCount: Int) -> Double {
        if let url = AudioStore.url(for: filename),
           let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 {
            return player.duration
        }
        return max(1, Double(fallbackWordCount) / 150 * 60)
    }

    /// Rough per-transcript cost: two passes (cheap extract + stronger critic),
    /// tokens ≈ chars/4 plus prompt/profile overhead. Precise token accounting is
    /// CE-5; this just keeps the running estimate honest enough to not surprise.
    private static func estimatedCost(forTranscriptChars chars: Int) -> Double {
        let promptTokens = max(200, chars / 4 + 400)
        let outputTokens = 250
        return CoachCostEstimator.usd(promptTokens: promptTokens, outputTokens: outputTokens, model: GeminiClient.Model.flashLite)
            + CoachCostEstimator.usd(promptTokens: promptTokens, outputTokens: outputTokens, model: GeminiClient.Model.flash)
    }
}
