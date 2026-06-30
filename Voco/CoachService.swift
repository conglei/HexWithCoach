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
import VocoCore
import Observation
import os
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
        // Resolve through the single source of truth (`CoachPaths`) so the writer
        // here and every reader (CoachProgress, CoachFocusModel, the seed) agree on
        // the path even on the no-entitlement / nil-container branch.
        LearnerProfileStore(url: CoachPaths.profileURL())
    }

    /// The append-only growth-history log (CI-13): one objective snapshot per
    /// analyzed note, the durable source the Review → progress trends read from.
    private var snapshotStore: CoachSnapshotStore {
        CoachSnapshotStore(url: CoachPaths.snapshotsURL())
    }

    /// Whether coaching is opted in with a usable key — gates the LLM override UI.
    var isReady: Bool { preferences.isReady }

    // MARK: - Automatic capture hook (CI-7 / ADR-0004)

    /// The single entry point the capture/save path calls after a note is
    /// transcribed (`DictationModel`). Runs the two lanes automatically:
    ///
    /// 1. **Objective lane** (free, local) — *always*, idempotently, in the
    ///    background. GOP (when the model is present) + fluency, persisted with the
    ///    note. This is what makes coaching "just appear" for free (ADR-0002/0004).
    /// 2. **LLM lane** (paid, BYOK) — only when opted in with a key AND the auto
    ///    toggle is on AND under budget; batched over the backlog, not per-note.
    ///
    /// Idempotent via `objectiveAnalyzedAt` so re-entry (re-save, launch sweep)
    /// doesn't redo finished work. Never throws to the caller — capture must not
    /// fail because coaching did.
    func autoAnalyzeOnCapture(_ entry: TranscriptEntry) async {
        await analyzeObjective(for: entry)
        await maybeAutoRunLLMBacklog()
    }

    /// Run the free objective lane for one note if it hasn't run yet (CI-7).
    /// Idempotent per `CoachAutomation.shouldRunObjective`: GOP (no-op without the
    /// phoneme model) + fluency patterns + keyless objective cards, all keyless. On
    /// success, stamps `objectiveAnalyzedAt` so it isn't redone. Safe to call from
    /// the capture hook and a launch backfill sweep.
    func analyzeObjective(for entry: TranscriptEntry) async {
        let inputs = CoachAutomation.ObjectiveInputs(alreadyAnalyzed: entry.objectiveAnalyzedAt != nil)
        guard CoachAutomation.shouldRunObjective(inputs) else { return }

        // GOP + pronunciation patterns (no-op when the phoneme model is absent) and
        // deterministic fluency patterns — independent of the BYOK key/budget.
        await analyzePronunciation(for: entry)
        recomputeFluencyPatterns()
        // Keyless teaching (CI-4b): turn the merged objective patterns into
        // deterministic CoachCards. NO LLM, NO network, NO budget.
        regenerateObjectiveCards()

        // Freeze this note's objective signals into the growth-history log so the
        // Review → progress trends have real data from day one (CI-13).
        recordSnapshot(for: entry)

        entry.objectiveAnalyzedAt = Date()
        try? modelContext.save()
    }

    /// Append (or refresh, keyed by note id) this note's objective signals to the
    /// growth-history log (CI-13). Keyless — runs for every analyzed note via the
    /// objective lane, so a real "how you grow over time" history exists without an
    /// API key. Captures GOP at analysis time so the pronunciation trend survives
    /// any later audio pruning. Best-effort: a snapshot write must never fail capture.
    private func recordSnapshot(for entry: TranscriptEntry) {
        let words = entry.text.split { $0.isWhitespace }.count
        let durationSec = duration(forAudio: entry.audioFilename, fallbackWordCount: words)
        let fluency = FluencyAnalyzer.analyze(
            transcript: entry.text,
            durationSec: durationSec,
            wordTimings: entry.wordTimings
        )
        let snapshot = CoachSnapshot(
            noteID: entry.id, date: entry.date,
            fluency: fluency, pronunciation: entry.pronunciationSignals
        )
        try? snapshotStore.record(snapshot)
    }

    /// Backfill the objective lane across every note that predates always-on
    /// capture (CI-7). Runs once at launch; bounded by `objectiveAnalyzedAt` so
    /// already-analyzed notes are skipped and the sweep is cheap on later launches.
    /// Keyless — no key/toggle/budget involved.
    func backfillObjectiveBacklog() async {
        let descriptor = FetchDescriptor<TranscriptEntry>(
            predicate: #Predicate { $0.objectiveAnalyzedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }
        for entry in pending {
            await analyzeObjective(for: entry)
        }
    }

    /// Automatically kick off a batched LLM-lane run when every gate holds
    /// (`CoachAutomation.shouldAutoRunLLM`): opted-in with a key, the auto toggle
    /// on, idle, real backlog, and under budget. The batched run itself
    /// (`analyzeBacklog`) re-checks the cap mid-run, so automatic spend stays
    /// bounded. No-op otherwise — including when the user turned auto off and only
    /// wants the manual "Review now" override.
    func maybeAutoRunLLMBacklog() async {
        let inputs = CoachAutomation.LLMInputs(
            isReady: preferences.isReady,
            autoEnabled: preferences.autoLLM,
            isIdle: !isAnalyzing,
            hasBacklog: backlogCount() > 0,
            underBudget: budget.canAnalyze(spentThisMonth: spentThisMonthUSD)
        )
        guard CoachAutomation.shouldAutoRunLLM(inputs) else { return }
        await analyzeBacklog()
    }

    /// Re-run the LLM lane on a single transcript (the manual override for one
    /// note): drop the LLM cards it previously produced, reset its analyzed flag,
    /// and analyze it again. Honors the same key/budget guards as the backlog run.
    /// Also refreshes the objective lane for the note. Automatic coaching flows
    /// through `autoAnalyzeOnCapture`; this stays as a manual escape hatch.
    func analyzeEntry(_ entry: TranscriptEntry) async {
        // DM-2 dedup: a manual re-analyze re-records this note's observations (both
        // the objective per-word GOP rows and the LLM-lane insight rows below), so
        // drop the note's existing `CoachObservation` rows first. Without this,
        // re-analyzing double-inserts and skews frequency-over-time queries.
        // `analyzeBacklog` doesn't need this — it only touches `coachAnalyzedAt == nil`
        // notes, which have no prior observations.
        TranscriptDeletion.deleteObservations(noteID: entry.id, in: modelContext)

        // Objective lane (keyless, CI-2/CI-3): force a refresh for this note even if
        // it ran before, so a manual re-analyze re-derives the objective signals too.
        entry.objectiveAnalyzedAt = nil
        await analyzeObjective(for: entry)

        guard preferences.isReady, !isAnalyzing else { return }
        guard let apiKey = CoachKeychain.read(CoachKeychain.geminiAPIKeyAccount), !apiKey.isEmpty else { return }
        guard budget.canAnalyze(spentThisMonth: spentThisMonthUSD) else {
            budgetReached = true
            return
        }
        budgetReached = false

        isAnalyzing = true
        defer { isAnalyzing = false }

        // Replace any LLM cards previously curated from this transcript. Objective
        // (keyless) cards are owned by `regenerateObjectiveCards()` above and keyed
        // by pattern, so they're excluded from this per-transcript LLM cleanup.
        if let existing = try? modelContext.fetch(FetchDescriptor<CoachCardEntity>()) {
            for card in existing
            where card.transcriptID == entry.id && !Self.isObjectiveCardKey(card.key) {
                modelContext.delete(card)
            }
        }
        entry.coachAnalyzedAt = nil

        let now = Date()
        let words = entry.text.split { $0.isWhitespace }.count
        let durationSec = duration(forAudio: entry.audioFilename, fallbackWordCount: words)

        // Too short to coach on — mark analyzed so it doesn't re-enter the backlog.
        guard durationSec >= Self.minDurationSec else {
            entry.coachAnalyzedAt = now
            try? modelContext.save()
            return
        }

        let pipeline = CoachPipeline(llm: GeminiCoachLLM(apiKey: apiKey))
        var profile = profileStore.load()
        let masteredBefore = Set(profile.patterns.filter { $0.status == .mastered }.map(\.key))
        let audioClip = audio(for: entry.audioFilename)
        let input = CoachTranscriptInput(
            id: entry.id, text: entry.text, durationSec: durationSec, audio: audioClip,
            wordTimings: entry.wordTimings,
            // Feed the objective GOP findings to the LLM as grounding (CI-6): the
            // model teaches around them, the objective lane owns detecting them.
            // Already computed above by analyzePronunciation when the model is present.
            pronunciationSignals: entry.pronunciationSignals
        )
        do {
            let analysis = try await pipeline.analyze(input, profile: &profile, at: now)
            recordSpend(Self.estimatedCost(chars: entry.text.count, audioSec: audioClip == nil ? 0 : durationSec))
            entry.coachAnalyzedAt = now

            // Persist every verified insight to the observation log (DM-2) BEFORE
            // curation discards the ones that don't become cards.
            recordObservations(analysis.insights, for: entry, origin: .llm)

            let wins = profile.patterns.filter { $0.status == .mastered && !masteredBefore.contains($0.key) }
            let merged = CoachAnalysis(insights: analysis.insights, focuses: [], signals: analysis.signals)
            let cards = CoachCardCurator.curate(analysis: merged, wins: wins, profile: profile, now: now, limit: perRunCardLimit)
            for card in cards { modelContext.insert(CoachCardEntity(card: card)) }
            try? profileStore.save(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
        try? modelContext.save()
    }

    // MARK: - Observation log (DM-2)

    /// Append every verified LLM-lane insight to the observation log *before*
    /// curation (DM-2). Today raw insights are discarded once curated into deduped
    /// cards; persisting each finding as a dated `CoachObservation` makes cross-note
    /// coaching (frequency over time, regression, evidence trails) a query. Curation
    /// and the profile are unchanged — this only ADDS persistence.
    ///
    /// `internal` (not `private`) so the persistence behavior is unit-testable via
    /// `@testable import Voco`.
    func recordObservations(_ insights: [CoachInsight], for entry: TranscriptEntry, origin: CoachObservation.Origin) {
        for insight in insights {
            let obs = CoachObservation()
            obs.noteID = entry.id
            obs.date = entry.date
            obs.lensRaw = insight.lens.rawValue
            obs.originRaw = origin.rawValue
            obs.patternKey = insight.key
            obs.severity = insight.severity
            obs.span = insight.originalSpan
            modelContext.insert(obs)
            HexLog.coach.debug("Coach observation: lens=\(insight.lens.rawValue, privacy: .public) key=\(insight.key, privacy: .public) span=\(insight.originalSpan, privacy: .private)")
        }
    }

    /// Append one objective `CoachObservation` per scored word from a pronunciation
    /// result (DM-2), recording the word + its GOP so per-word pronunciation trends
    /// across notes become a query. Keyless lane → origin `.objective`,
    /// `lens = .pronunciation`. `internal` for `@testable` unit coverage.
    func recordWordObservations(_ result: PronunciationResult, for entry: TranscriptEntry) {
        for wordScore in result.words {
            let obs = CoachObservation()
            obs.noteID = entry.id
            obs.date = entry.date
            obs.lensRaw = Lens.pronunciation.rawValue
            obs.originRaw = CoachObservation.Origin.objective.rawValue
            obs.word = wordScore.word
            obs.gop = wordScore.gop
            modelContext.insert(obs)
        }
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

            // Send the audio too (multimodal lens) so the model can hear intonation
            // & stress (CI-6), not just read the transcript. The objective GOP +
            // fluency findings ride along as grounding — the LLM teaches around them
            // rather than re-detecting pronunciation/timing.
            let audioClip = audio(for: entry.audioFilename)
            let input = CoachTranscriptInput(
                id: entry.id, text: entry.text, durationSec: durationSec, audio: audioClip,
                wordTimings: entry.wordTimings,
                pronunciationSignals: entry.pronunciationSignals
            )
            do {
                let analysis = try await pipeline.analyze(input, profile: &profile, at: now)
                // Persist this note's verified insights to the observation log (DM-2)
                // inside the loop, while we still have its id/date — BEFORE the batch
                // curation below collapses them into deduped cards.
                recordObservations(analysis.insights, for: entry, origin: .llm)
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

        // Refresh keyless objective cards from the now-updated profile so the feed
        // carries both lanes (CI-4b). The LLM lane above *enriches* alongside — it
        // doesn't replace these pattern-keyed cards.
        regenerateObjectiveCards()
    }

    // MARK: - Pronunciation (objective lane, CI-3)

    /// Compute + persist the on-device GOP `PronunciationResult` for a note when
    /// the phoneme model is present (gated on `PronunciationAssets.ready`), then
    /// re-derive per-speaker-relative pronunciation patterns across the corpus and
    /// merge them into the profile. Deterministic + keyless: NO LLM, NO network.
    ///
    /// No-op when the model assets are absent (keyless-no-model state) — the rest
    /// of coaching still works and GOP can backfill once the model arrives. Safe
    /// to call repeatedly; an entry that already has a result is not re-analyzed.
    func analyzePronunciation(for entry: TranscriptEntry) async {
        guard PronunciationAssets.ready else { return }

        // 1. Compute + persist this note's result if we don't have one yet.
        if entry.pronunciationResult == nil,
           let url = AudioStore.url(for: entry.audioFilename) {
            let text = entry.text
            let result = await Self.runPronunciation(audioURL: url, transcript: text)
            if let result, !result.words.isEmpty {
                entry.pronunciationResult = result
                // Append one objective observation per scored word to the log (DM-2),
                // capturing the per-word GOP so cross-note pronunciation trends are a
                // query. Keyless lane → origin `.objective`.
                recordWordObservations(result, for: entry)
                try? modelContext.save()
            }
        }

        // 2. Re-derive patterns over the full corpus and merge into the profile.
        recomputePronunciationPatterns()
    }

    /// Gather every note's persisted pronunciation signals into the detector's
    /// corpus, run the pure per-speaker-relative + recurrence detector, and merge
    /// the resulting patterns into the LearnerProfile. Pure logic lives in HexCore.
    func recomputePronunciationPatterns() {
        let descriptor = FetchDescriptor<TranscriptEntry>(sortBy: [SortDescriptor(\.date)])
        guard let all = try? modelContext.fetch(descriptor) else { return }
        let corpus: [PronunciationPatternDetector.Note] = all.compactMap { entry in
            guard let signals = entry.pronunciationSignals else { return nil }
            return PronunciationPatternDetector.Note(transcriptID: entry.id, signals: signals)
        }
        guard !corpus.isEmpty else { return }

        let observations = PronunciationPatternDetector.detect(corpus: corpus)
        guard !observations.isEmpty else { return }

        var profile = profileStore.load()
        profile.integrate(observations, at: Date())
        try? profileStore.save(profile)
    }

    // MARK: - Fluency (objective lane, CI-2)

    /// Compute deterministic objective fluency signals for every note, run the pure
    /// fillers/long-pauses/restarts detector (absolute thresholds + recurrence +
    /// cold-start; pace stays informational, never a pattern), and merge the
    /// resulting prosody patterns into the LearnerProfile. Keyless: NO LLM, NO
    /// network, NO model. The same fluency numbers also flow to the LLM as grounding
    /// in `CoachPipeline` (via `CoachTranscriptInput`); this lane only authors the
    /// free objective patterns (ADR-0001, ADR-0004). Pure logic lives in HexCore.
    func recomputeFluencyPatterns() {
        let descriptor = FetchDescriptor<TranscriptEntry>(sortBy: [SortDescriptor(\.date)])
        guard let all = try? modelContext.fetch(descriptor) else { return }

        let corpus: [FluencyPatternDetector.Note] = all.map { entry in
            let words = entry.text.split { $0.isWhitespace }.count
            let durationSec = duration(forAudio: entry.audioFilename, fallbackWordCount: words)
            let signals = FluencyAnalyzer.analyze(
                transcript: entry.text,
                durationSec: durationSec,
                wordTimings: entry.wordTimings
            )
            return FluencyPatternDetector.Note(transcriptID: entry.id, signals: signals)
        }
        guard !corpus.isEmpty else { return }

        let observations = FluencyPatternDetector.detect(corpus: corpus)
        guard !observations.isEmpty else { return }

        var profile = profileStore.load()
        profile.integrate(observations, at: Date())
        try? profileStore.save(profile)
    }

    // MARK: - Objective card generation (keyless teaching, CI-4b)

    /// Regenerate the deterministic keyless cards from the objective patterns in
    /// the profile (phoneme guide + fluency-tips + the learner's own examples) and
    /// persist them. Pure generation lives in `ObjectiveCardGenerator` (HexCore);
    /// this only owns the SwiftData upsert. NO LLM, NO network, NO budget.
    ///
    /// Idempotent: it deletes the prior objective-keyed cards and re-inserts the
    /// current set, so repeated calls (per-note + backlog) don't accumulate dupes.
    /// LLM cards are untouched — when a key is present the LLM lane *enriches*
    /// alongside these rather than replacing them.
    func regenerateObjectiveCards() {
        let now = Date()
        let profile = profileStore.load()
        let cards = ObjectiveCardGenerator.generate(profile: profile, now: now)

        // Drop the previous objective cards (pattern-keyed), keep LLM cards.
        if let existing = try? modelContext.fetch(FetchDescriptor<CoachCardEntity>()) {
            for card in existing where Self.isObjectiveCardKey(card.key) {
                modelContext.delete(card)
            }
        }
        for card in cards { modelContext.insert(CoachCardEntity(card: card)) }
        try? modelContext.save()
    }

    /// Whether a persisted card's key belongs to the keyless objective lane
    /// (pronunciation-phoneme or fluency patterns). Used to scope objective-card
    /// cleanup without disturbing LLM cards. Mirrors the detectors' key prefixes.
    private static func isObjectiveCardKey(_ key: String) -> Bool {
        key.hasPrefix(ObjectiveCardGenerator.pronunciationKeyPrefix)
            || key.hasPrefix(ObjectiveCardGenerator.fluencyKeyPrefix)
    }

    /// Run the analyzer off the main actor. Returns nil if assets fail to load or
    /// analysis throws (e.g. clip too short / out-of-dictionary words).
    private static func runPronunciation(audioURL: URL, transcript: String) async -> PronunciationResult? {
        await Task.detached(priority: .utility) { () -> PronunciationResult? in
            guard let modelURL = PronunciationAssets.model(),
                  let vocabURL = PronunciationAssets.vocab(),
                  let dictURL = PronunciationAssets.cmudict(),
                  let analyzer = PronunciationAnalyzer(modelURL: modelURL, vocabURL: vocabURL, cmudictURL: dictURL)
            else { return nil }
            do {
                let samples = try PhonemeRecognizer.loadSamples(url: audioURL)
                return try analyzer.analyze(samples: samples, transcript: transcript)
            } catch {
                HexLog.pronunciation.error("CoachService GOP analyze failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
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

    /// Rough per-transcript cost: audio-grounded extract + critic, both on `flash`.
    /// The critic only carries audio when a candidate needs it; we can't know that
    /// here pre-analysis, so we price the audio into extract only (the critic's
    /// audio, when present, is the conservative-but-uncommon case). Precise token
    /// accounting is CE-5; this keeps the running estimate honest enough to not
    /// surprise.
    private static func estimatedCost(chars: Int, audioSec: Double) -> Double {
        let audioTokens = Int(audioSec * 32)
        let extractPrompt = max(200, chars / 4 + 400 + audioTokens)
        let criticPrompt = max(200, chars / 4 + 400)
        let output = 250
        return CoachCostEstimator.usd(promptTokens: extractPrompt, outputTokens: output, model: GeminiClient.Model.flash)
            + CoachCostEstimator.usd(promptTokens: criticPrompt, outputTokens: output, model: GeminiClient.Model.flash)
    }
}
