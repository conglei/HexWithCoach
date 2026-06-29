//
//  MacCoachService.swift
//  VocoMac
//
//  macOS Coach v2 driver (MC-R4). Orchestrates the two coaching lanes over the
//  shared SwiftData store (`MacTranscriptStore`'s `ModelContext`), mirroring iOS
//  `Voco/CoachService.swift` behavior exactly:
//
//    • Objective lane (free, local, keyless) — runs at capture and on a launch
//      backfill, idempotent via `TranscriptEntry.objectiveAnalyzedAt`. Computes
//      GOP (when the phoneme model is present), deterministic fluency patterns,
//      keyless objective cards, a growth snapshot, and appends one `.objective`
//      `CoachObservation` per scored word.
//    • LLM lane (paid, BYOK) — auto-batched over the un-analyzed backlog at launch,
//      gated by opt-in + key + `CoachBudget`, idempotent via `coachAnalyzedAt`.
//      Persists every verified insight as an `.llm` `CoachObservation` BEFORE
//      curation, then curates `CoachCardEntity` rows and updates the profile.
//
//  DELIBERATE DEVIATION FROM MC-5: the old MC-5 moved iOS `CoachService` into
//  `VocoEngine` to share it. We do NOT do that here — `Voco/CoachService.swift` is
//  the hottest file on `origin/main` (DM-2 + #81–#89), and sharing it would cause
//  recurring merge conflicts. Instead this is a macOS-specific driver built by
//  reusing the already-shared VocoCore/VocoEngine primitives (CoachPipeline,
//  FluencyAnalyzer, the pattern detectors, ObjectiveCardGenerator,
//  CoachCardCurator, CoachBudget, CoachAutomation, GeminiCoachLLM, CoachKeychain).
//  A future cleanup could extract a shared `CoachRunner` into VocoCore used by both
//  iOS and macOS — out of scope for MC-R4.
//

import AVFoundation
import Foundation
import VocoCore
import Observation
import os
import SwiftData

/// macOS implementation of the Coach v2 two-lane engine. `@MainActor @Observable`
/// so Settings can bind to its budget / spend / `budgetReached` state directly,
/// matching iOS. Owns no `ModelContext` of its own — it is handed the shared
/// container's context by `MacTranscriptStore` at bootstrap.
@MainActor
@Observable
final class MacCoachService {
    private let modelContext: ModelContext
    private let preferences: MacCoachPreferences

    private(set) var isAnalyzing = false
    var errorMessage: String?

    /// Accumulated estimated BYOK spend (USD), persisted in the App Group so the
    /// user can see it in Settings (mirrors iOS).
    private(set) var totalCostUSD: Double

    /// The monthly cost cap. Persisted in the App Group; setting it writes through
    /// so the next run honors it immediately.
    var budget: CoachBudget {
        didSet {
            if let cap = budget.monthlyCapUSD {
                defaults.set(cap, forKey: Self.capKey)
            } else {
                defaults.removeObject(forKey: Self.capKey)
            }
        }
    }

    /// Set when a run stopped because this month's spend hit the cap — surfaced in
    /// Settings so the user knows why coaching paused.
    private(set) var budgetReached = false

    /// Cost/volume bounds per run.
    var perRunTranscriptLimit = 20
    var perRunCardLimit = 7

    private let defaults = UserDefaults(suiteName: HexAppGroup.identifier) ?? .standard
    // Identical keys to iOS `CoachService` so the spend ledger is shared per device.
    @ObservationIgnored private static let costKey = "hex.coach.totalCostUSD"
    @ObservationIgnored private static let capKey = "hex.coach.monthlyCapUSD"
    @ObservationIgnored private static let spendKeyPrefix = "hex.coach.spend."

    init(modelContext: ModelContext, preferences: MacCoachPreferences) {
        self.modelContext = modelContext
        self.preferences = preferences
        totalCostUSD = defaults.double(forKey: Self.costKey)
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

    /// File-backed growth-history log, resolved the same way iOS does (App Group
    /// `Coach/snapshots.json`, temp dir fallback) so both platforms write the same
    /// file under the shared App Group.
    private var snapshotStore: CoachSnapshotStore {
        CoachSnapshotStore(url: Self.coachDir.appendingPathComponent("snapshots.json"))
    }

    /// File-backed LearnerProfile, resolved like iOS (App Group `Coach/profile.json`).
    private var profileStore: LearnerProfileStore {
        LearnerProfileStore(url: Self.coachDir.appendingPathComponent("profile.json"))
    }

    private static var coachDir: URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HexAppGroup.identifier)?
            .appendingPathComponent("Coach", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
    }

    /// Whether coaching is opted in with a usable key.
    var isReady: Bool { preferences.isReady }

    // MARK: - Automatic capture hook (mirrors iOS `autoAnalyzeOnCapture`)

    /// The single entry point the capture/save path calls after a note is
    /// transcribed (`MacTranscriptStore.insert`). Runs the two lanes automatically:
    /// objective always (free, idempotent), then the LLM lane if every gate holds.
    /// Never throws — capture must not fail because coaching did.
    func autoAnalyzeOnCapture(_ entry: TranscriptEntry) async {
        await analyzeObjective(for: entry)
        await maybeAutoRunLLMBacklog()
    }

    /// Run the free objective lane for one note if it hasn't run yet. Idempotent
    /// per `CoachAutomation.shouldRunObjective`: GOP (no-op without the phoneme
    /// model) + fluency patterns + keyless objective cards + a growth snapshot,
    /// all keyless. Stamps `objectiveAnalyzedAt` on success.
    func analyzeObjective(for entry: TranscriptEntry) async {
        let inputs = CoachAutomation.ObjectiveInputs(alreadyAnalyzed: entry.objectiveAnalyzedAt != nil)
        guard CoachAutomation.shouldRunObjective(inputs) else { return }

        await analyzePronunciation(for: entry)
        recomputeFluencyPatterns()
        regenerateObjectiveCards()
        recordSnapshot(for: entry)

        entry.objectiveAnalyzedAt = Date()
        try? modelContext.save()
    }

    /// Append (or refresh, keyed by note id) this note's objective signals to the
    /// growth-history log. Keyless; best-effort (a snapshot write must never fail
    /// capture). Captures GOP at analysis time so the trend survives audio pruning.
    private func recordSnapshot(for entry: TranscriptEntry) {
        let words = entry.text.split { $0.isWhitespace }.count
        let durationSec = duration(forEntry: entry, fallbackWordCount: words)
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
    /// capture. Runs once at launch; bounded by `objectiveAnalyzedAt`. Keyless.
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
    /// on, idle, real backlog, under budget. No-op otherwise.
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

    /// Launch pass: refresh the keyless objective backlog, then (if gated) run the
    /// LLM backlog. Called once from `HexAppDelegate` after bootstrap.
    func runLaunchPasses() async {
        await backfillObjectiveBacklog()
        await maybeAutoRunLLMBacklog()
    }

    // MARK: - Observation log (DM-2)

    /// Append every verified LLM-lane insight to the observation log *before*
    /// curation, so cross-note coaching (frequency over time, regression, evidence
    /// trails) becomes a query. Mirrors iOS `recordObservations`.
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
            HexLog.coach.debug("Mac coach observation: lens=\(insight.lens.rawValue, privacy: .public) key=\(insight.key, privacy: .public) span=\(insight.originalSpan, privacy: .private)")
        }
    }

    /// Append one objective `CoachObservation` per scored word from a pronunciation
    /// result, recording word + GOP so per-word pronunciation trends become a query.
    /// Keyless lane → origin `.objective`, `lens = .pronunciation`. Mirrors iOS.
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

    /// Delete every `CoachObservation` for a note (DM-2 dedup) — used by the manual
    /// re-analyze path so re-recording doesn't double-count. Mirrors iOS
    /// `TranscriptDeletion.deleteObservations`.
    private func deleteObservations(noteID: UUID) {
        guard let rows = try? modelContext.fetch(
            FetchDescriptor<CoachObservation>(predicate: #Predicate { $0.noteID == noteID })
        ) else { return }
        for row in rows { modelContext.delete(row) }
    }

    /// Count of transcripts not yet analyzed by the LLM lane — the refresh badge.
    func backlogCount() -> Int {
        let descriptor = FetchDescriptor<TranscriptEntry>(predicate: #Predicate { $0.coachAnalyzedAt == nil })
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - LLM lane

    /// Re-run the LLM lane on a single transcript (manual override): drop its prior
    /// observations + LLM cards, reset its flags, refresh the objective lane, then
    /// re-analyze under the same key/budget guards. Mirrors iOS `analyzeEntry`.
    func analyzeEntry(_ entry: TranscriptEntry) async {
        deleteObservations(noteID: entry.id)

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

        if let existing = try? modelContext.fetch(FetchDescriptor<CoachCardEntity>()) {
            for card in existing
            where card.transcriptID == entry.id && !Self.isObjectiveCardKey(card.key) {
                modelContext.delete(card)
            }
        }
        entry.coachAnalyzedAt = nil

        let now = Date()
        let words = entry.text.split { $0.isWhitespace }.count
        let durationSec = duration(forEntry: entry, fallbackWordCount: words)

        guard durationSec >= Self.minDurationSec else {
            entry.coachAnalyzedAt = now
            try? modelContext.save()
            return
        }

        let pipeline = CoachPipeline(llm: GeminiCoachLLM(apiKey: apiKey))
        var profile = profileStore.load()
        let masteredBefore = Set(profile.patterns.filter { $0.status == .mastered }.map(\.key))
        let audioClip = audio(for: entry)
        let input = CoachTranscriptInput(
            id: entry.id, text: entry.text, durationSec: durationSec, audio: audioClip,
            wordTimings: entry.wordTimings,
            pronunciationSignals: entry.pronunciationSignals
        )
        do {
            let analysis = try await pipeline.analyze(input, profile: &profile, at: now)
            recordSpend(Self.estimatedCost(chars: entry.text.count, audioSec: audioClip == nil ? 0 : durationSec))
            entry.coachAnalyzedAt = now

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

    /// Analyze a bounded slice of the un-analyzed backlog and produce cards.
    /// No-op unless opted in with a key + under budget. Mirrors iOS `analyzeBacklog`.
    func analyzeBacklog() async {
        guard preferences.isReady, !isAnalyzing else { return }
        guard let apiKey = CoachKeychain.read(CoachKeychain.geminiAPIKeyAccount), !apiKey.isEmpty else { return }

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
            let durationSec = duration(forEntry: entry, fallbackWordCount: words)

            if durationSec < Self.minDurationSec {
                entry.coachAnalyzedAt = now
                continue
            }

            let audioClip = audio(for: entry)
            let input = CoachTranscriptInput(
                id: entry.id, text: entry.text, durationSec: durationSec, audio: audioClip,
                wordTimings: entry.wordTimings,
                pronunciationSignals: entry.pronunciationSignals
            )
            do {
                let analysis = try await pipeline.analyze(input, profile: &profile, at: now)
                recordObservations(analysis.insights, for: entry, origin: .llm)
                allInsights.append(contentsOf: analysis.insights)
                let cost = Self.estimatedCost(chars: entry.text.count, audioSec: audioClip == nil ? 0 : durationSec)
                recordSpend(cost)
                entry.coachAnalyzedAt = now
            } catch {
                errorMessage = error.localizedDescription
                break
            }

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

        regenerateObjectiveCards()
    }

    // MARK: - Pronunciation (objective lane)

    /// Compute + persist the on-device GOP `PronunciationResult` for a note when the
    /// phoneme model is present, append per-word `.objective` observations, then
    /// re-derive corpus pronunciation patterns into the profile. No-op without the
    /// model. Mirrors iOS `analyzePronunciation`.
    func analyzePronunciation(for entry: TranscriptEntry) async {
        guard MacPronunciationAssets.ready else { return }

        if entry.pronunciationResult == nil,
           let url = MacCoachService.audioURL(for: entry) {
            let text = entry.text
            let result = await Self.runPronunciation(audioURL: url, transcript: text)
            if let result, !result.words.isEmpty {
                entry.pronunciationResult = result
                recordWordObservations(result, for: entry)
                try? modelContext.save()
            }
        }

        recomputePronunciationPatterns()
    }

    /// Gather every note's persisted pronunciation signals, run the pure detector,
    /// merge resulting patterns into the LearnerProfile. Mirrors iOS.
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

    // MARK: - Fluency (objective lane)

    /// Compute deterministic objective fluency signals for every note, run the pure
    /// detector, merge resulting prosody patterns into the LearnerProfile. Keyless.
    /// Mirrors iOS `recomputeFluencyPatterns`.
    func recomputeFluencyPatterns() {
        let descriptor = FetchDescriptor<TranscriptEntry>(sortBy: [SortDescriptor(\.date)])
        guard let all = try? modelContext.fetch(descriptor) else { return }

        let corpus: [FluencyPatternDetector.Note] = all.map { entry in
            let words = entry.text.split { $0.isWhitespace }.count
            let durationSec = duration(forEntry: entry, fallbackWordCount: words)
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

    // MARK: - Objective card generation (keyless teaching)

    /// Regenerate the deterministic keyless cards from the objective patterns in the
    /// profile and persist them. Idempotent: drops prior objective-keyed cards and
    /// re-inserts the current set; LLM cards untouched. Mirrors iOS.
    func regenerateObjectiveCards() {
        let now = Date()
        let profile = profileStore.load()
        let cards = ObjectiveCardGenerator.generate(profile: profile, now: now)

        if let existing = try? modelContext.fetch(FetchDescriptor<CoachCardEntity>()) {
            for card in existing where Self.isObjectiveCardKey(card.key) {
                modelContext.delete(card)
            }
        }
        for card in cards { modelContext.insert(CoachCardEntity(card: card)) }
        try? modelContext.save()
    }

    private static func isObjectiveCardKey(_ key: String) -> Bool {
        key.hasPrefix(ObjectiveCardGenerator.pronunciationKeyPrefix)
            || key.hasPrefix(ObjectiveCardGenerator.fluencyKeyPrefix)
    }

    /// Run the analyzer off the main actor. nil if assets fail to load or analysis
    /// throws. Mirrors iOS.
    private static func runPronunciation(audioURL: URL, transcript: String) async -> PronunciationResult? {
        await Task.detached(priority: .utility) { () -> PronunciationResult? in
            guard let modelURL = MacPronunciationAssets.model(),
                  let vocabURL = MacPronunciationAssets.vocab(),
                  let dictURL = MacPronunciationAssets.cmudict(),
                  let analyzer = PronunciationAnalyzer(modelURL: modelURL, vocabURL: vocabURL, cmudictURL: dictURL)
            else { return nil }
            do {
                let samples = try PhonemeRecognizer.loadSamples(url: audioURL)
                return try analyzer.analyze(samples: samples, transcript: transcript)
            } catch {
                HexLog.pronunciation.error("Mac CoachService GOP analyze failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    // MARK: - Helpers

    /// Below this, a dictation is too short to coach on — skip it.
    private static let minDurationSec: Double = 10

    /// On-disk audio URL for a note, in the Mac `Recordings/` dir, or nil when not
    /// recoverable. Static so `runPronunciation` (off-actor setup) can reuse it.
    static func audioURL(for entry: TranscriptEntry) -> URL? {
        guard let filename = entry.audioFilename, !filename.isEmpty else { return nil }
        let url = MacTranscriptStore.recordingsURL(for: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Real audio duration when the row didn't carry one and the file is on disk;
    /// otherwise the row's stored `duration`, falling back to a ~150 wpm estimate.
    private func duration(forEntry entry: TranscriptEntry, fallbackWordCount: Int) -> Double {
        if entry.duration > 0 { return entry.duration }
        if let url = MacCoachService.audioURL(for: entry),
           let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 {
            return player.duration
        }
        return max(1, Double(fallbackWordCount) / 150 * 60)
    }

    /// Load a note's retained audio for the multimodal lens (nil if none).
    private func audio(for entry: TranscriptEntry) -> CoachAudio? {
        guard let url = MacCoachService.audioURL(for: entry), let data = try? Data(contentsOf: url) else { return nil }
        return CoachAudio(data: data, mimeType: "audio/wav")
    }

    /// Rough per-transcript cost: audio-grounded extract + critic on `flash`.
    /// Mirrors iOS `estimatedCost`.
    private static func estimatedCost(chars: Int, audioSec: Double) -> Double {
        let audioTokens = Int(audioSec * 32)
        let extractPrompt = max(200, chars / 4 + 400 + audioTokens)
        let criticPrompt = max(200, chars / 4 + 400)
        let output = 250
        return CoachCostEstimator.usd(promptTokens: extractPrompt, outputTokens: output, model: GeminiClient.Model.flash)
            + CoachCostEstimator.usd(promptTokens: criticPrompt, outputTokens: output, model: GeminiClient.Model.flash)
    }
}

/// Locates the phoneme model + vocab + CMUdict on macOS. Looks in the app bundle
/// (Xcode compiles a bundled `.mlpackage` → `.mlmodelc`), then Application Support
/// (`Pronunciation/`) for side-loaded assets. Mirrors iOS `PronunciationAssets`.
/// The GOP model is not bundled in the Mac app today, so this typically returns
/// nil and the objective lane runs fluency-only (GOP is a documented no-op).
nonisolated enum MacPronunciationAssets {
    static var ready: Bool { model() != nil && vocab() != nil && cmudict() != nil }

    static func model() -> URL? {
        Bundle.main.url(forResource: "PhonemeCTC", withExtension: "mlmodelc") ?? sideloaded("PhonemeCTC.mlpackage")
    }
    static func vocab() -> URL? {
        Bundle.main.url(forResource: "phoneme_vocab", withExtension: "json") ?? sideloaded("phoneme_vocab.json")
    }
    static func cmudict() -> URL? {
        Bundle.main.url(forResource: "cmudict", withExtension: "dict") ?? sideloaded("cmudict.dict")
    }

    private static func sideloaded(_ name: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pronunciation", isDirectory: true) else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
