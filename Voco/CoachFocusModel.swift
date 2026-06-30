//
//  CoachFocusModel.swift
//  Voco
//
//  CF-1 — the app-side bridge between the persisted Coach data (the SwiftData
//  `CoachObservation` log + the file-backed `LearnerProfile` / `CoachSnapshot`s)
//  and the PURE `CoachFocusEngine` / `CoachWeeklySummaryGenerator` in VocoCore.
//
//  It does three things, all thin:
//    1. Maps each `CoachObservation` row onto a pure `ObservationFact` — including
//       turning the objective per-word GOP rows into a stable per-word key + a
//       severity derived from how bad the GOP is (the store leaves objective rows
//       at severity 0; ranking needs a 1…5 impact).
//    2. Calls the pure engine to build the `CoachFocusSurface` (skill map + the one
//       prioritized focus) — the calibrated ranking lives entirely in VocoCore.
//    3. Generates the weekly summary ONCE and caches it (grounded LLM recap when a
//       key is present, structured template otherwise), so opening the Coach tab
//       never triggers a per-view LLM call (CE-5 cadence control).
//
//  Pure ranking/summary logic is NOT here — this only reads existing data and
//  feeds the engine, so the de-overwhelm calibration stays fast-testable in
//  `swift test`.
//

import Foundation
import VocoCore
import Observation
import SwiftData

@MainActor
@Observable
final class CoachFocusModel {
    /// The computed surface (skill map + prioritized focus + lead win). Empty until
    /// `reload` runs.
    private(set) var surface = CoachFocusSurface(skillMap: [], focuses: [], leadWin: nil)
    /// CF-3 — the "today / this week you practiced" accumulation strip, computed from
    /// the persisted `PracticeAttempt` rows. Empty until `reload` runs (and stays
    /// `isEmpty` when nothing was practiced this week, so the strip hides).
    private(set) var practice = PracticeSummary(repsToday: 0, repsThisWeek: 0, byLens: [])
    /// CF-3 — the practice→frequency-drop signal for the hero focus, when one cleared
    /// the evidence bar AND its trend genuinely improved after practice. nil otherwise
    /// (the honesty guard: we never show a "it's working" claim on noise).
    private(set) var heroTrend: FrequencyTrend?
    /// The deterministic stats block (minutes spoken / notes / fillers per minute) —
    /// computed entirely by us, never by the LLM. Rendered as labeled metrics.
    private(set) var stats = CoachStats(minutesSpoken: 0, noteCount: 0)
    /// The qualitative weekly recap (number-free). nil until generated; persisted
    /// per-week so it's stable across tab visits and only regenerates when the week
    /// rolls over or the grounded inputs change.
    private(set) var summary: CoachWeeklySummary?
    /// Whether the recap is being (re)generated — lets the UI show a placeholder.
    private(set) var isGeneratingSummary = false

    private let modelContext: ModelContext
    private let preferences: CoachPreferences

    init(modelContext: ModelContext, preferences: CoachPreferences) {
        self.modelContext = modelContext
        self.preferences = preferences
    }

    // MARK: - File-backed stores

    /// Resolve through the single source of truth (`CoachPaths`) so this surface
    /// reads exactly the files `CoachService` writes and `DebugSeed` seeds — on the
    /// entitled device AND the no-entitlement (nil-container) simulator/test branch.
    private var profileStore: LearnerProfileStore {
        LearnerProfileStore(url: CoachPaths.profileURL())
    }

    private var snapshotStore: CoachSnapshotStore {
        CoachSnapshotStore(url: CoachPaths.snapshotsURL())
    }

    /// The per-week recap cache (CF-fix), beside profile/snapshots in the Coach dir.
    private var summaryCache: CoachSummaryCacheStore {
        CoachSummaryCacheStore(url: CoachPaths.weeklySummaryURL())
    }

    // MARK: - Reload

    /// Recompute the surface and (re)generate the cached weekly summary. Called when
    /// the Focus surface appears and after an analysis run finishes. Cheap: the
    /// ranking is pure; the only potentially-slow step is the grounded LLM recap,
    /// which is awaited once here and then cached.
    func reload(now: Date = Date()) async {
        let profile = profileStore.load()
        let log = snapshotStore.load()
        let facts = loadFacts()
        let weekly = log.weekly()

        let computed = CoachFocusEngine.surface(facts: facts, profile: profile, weekly: weekly, now: now)
        surface = computed

        // CF-3 — accumulation + the practice→frequency-drop loop, both pure VocoCore.
        let practiceFacts = loadPracticeFacts()
        practice = PracticeLog.summary(facts: practiceFacts, now: now)
        // Close the loop on the hero focus: only surface its trend when the honesty
        // guard says practicing it genuinely reduced its frequency.
        if let hero = computed.heroFocus {
            let trend = FrequencyTrend.make(
                lens: hero.lens, patternKey: hero.key,
                observations: facts, practiceFacts: practiceFacts, now: now
            )
            heroTrend = trend.didImprove ? trend : nil
        } else {
            heroTrend = nil
        }

        // CF-fix — split the card into a deterministic stats block (numbers computed
        // by us) and a number-free qualitative recap.
        stats = CoachStats.make(weekly: weekly)

        // The recap is built from NUMBER-FREE findings only, then cached per ISO week
        // keyed by a stable hash of that input. Reuse the persisted recap when the
        // week + inputs are unchanged — so a normal tab glance triggers NO LLM call
        // and the wording never drifts. Regenerate only on a week rollover or an
        // input change.
        let recapInput = CoachRecapInput.make(surface: computed)
        let key = CoachSummaryCacheKey.make(input: recapInput, now: now)
        if let cached = summaryCache.fresh(for: key) {
            summary = cached
            isGeneratingSummary = false
            return
        }

        isGeneratingSummary = true
        let generator = CoachWeeklySummaryGenerator(llm: makeLLM())
        let result = await generator.generate(recapInput)
        summary = result
        isGeneratingSummary = false
        // Persist so the next visit (same week, same inputs) reuses it verbatim.
        try? summaryCache.save(CoachSummaryCacheEntry(key: key, summary: result, generatedAt: now))
    }

    /// The pattern the hero focus came from, for the lens-detail drill-down (its
    /// examples + the teachable rule live on the profile pattern).
    func pattern(for focus: FocusArea) -> RecurringPattern? {
        profileStore.load().patterns.first { $0.lens == focus.lens && $0.key == focus.key }
    }

    // MARK: - Observation → fact mapping

    /// Read every `CoachObservation` and map it onto a pure `ObservationFact`.
    ///
    /// - LLM-lane rows carry a `patternKey` + a real `severity` + a `span` — mapped
    ///   straight through.
    /// - Objective per-word GOP rows carry a `word` + a `gop` (≤ 0) but no key and
    ///   severity 0. We key them `gop-<word>` so repeated mispronunciations of the
    ///   same word merge, and derive a 1…5 severity from the GOP (more negative =
    ///   worse). The word itself is the example "span".
    private func loadFacts() -> [ObservationFact] {
        guard let rows = try? modelContext.fetch(FetchDescriptor<CoachObservation>()) else { return [] }
        return rows.compactMap { obs -> ObservationFact? in
            switch obs.origin {
            case .llm:
                guard let key = obs.patternKey, !key.isEmpty else { return nil }
                return ObservationFact(
                    lens: obs.lens, key: key,
                    severity: obs.severity, date: obs.date, span: obs.span)
            case .objective:
                // Per-word GOP findings (pronunciation). Need a stable key + severity.
                if let word = obs.word, !word.isEmpty {
                    return ObservationFact(
                        lens: .pronunciation, key: "gop-\(word.lowercased())",
                        severity: Self.severity(forGOP: obs.gop), date: obs.date, span: word)
                }
                // Objective non-pronunciation rows that happen to carry a patternKey
                // (e.g. fluency patterns) still rank by their key.
                if let key = obs.patternKey, !key.isEmpty {
                    return ObservationFact(
                        lens: obs.lens, key: key,
                        severity: max(1, obs.severity), date: obs.date, span: obs.span)
                }
                return nil
            }
        }
    }

    // MARK: - Practice attempt → fact mapping (CF-3)

    /// Read every persisted `PracticeAttempt` and map it onto a pure
    /// `PracticeAttemptFact`, carrying the parent `PracticeItem`'s CF-3 tags (lens +
    /// patternKey) and CF-2 kind. The attempt's `score` is the mean of its
    /// per-segment ASR-match scores (shadow) or the single word-swap judge score.
    /// Attempts whose item was deleted (no parent) are skipped — there's nothing to
    /// attribute them to.
    private func loadPracticeFacts() -> [PracticeAttemptFact] {
        guard let rows = try? modelContext.fetch(FetchDescriptor<PracticeAttempt>()) else { return [] }
        return rows.compactMap { attempt -> PracticeAttemptFact? in
            guard let item = attempt.item else { return nil }
            let scores = attempt.perSegmentScores
            let score = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
            return PracticeAttemptFact(
                date: attempt.date,
                kind: item.kind,
                lens: item.lens,
                patternKey: item.patternKey,
                score: score,
                gopDelta: attempt.gopDelta
            )
        }
    }

    /// Map a goodness-of-pronunciation score (≤ 0; closer to 0 = better) onto the
    /// ranking's 1…5 severity. Thresholds are gentle: a fluent speaker's pronunciation
    /// rarely deserves a focus, which the low pronunciation lens weight already
    /// enforces — this just gives the worst sounds a higher impact within the lens.
    nonisolated static func severity(forGOP gop: Double?) -> Int {
        guard let gop else { return 1 }
        switch gop {
        case ..<(-5): return 5
        case ..<(-4): return 4
        case ..<(-3): return 3
        case ..<(-2): return 2
        default: return 1
        }
    }

    // MARK: - LLM seam

    /// The provider adapter for the grounded recap — only when opted in with a key.
    /// nil forces the keyless template path (which is the common case and the
    /// guaranteed floor).
    private func makeLLM() -> CoachLLM? {
        guard preferences.isReady,
              let apiKey = CoachKeychain.read(CoachKeychain.geminiAPIKeyAccount),
              !apiKey.isEmpty
        else { return nil }
        return GeminiCoachLLM(apiKey: apiKey)
    }
}
