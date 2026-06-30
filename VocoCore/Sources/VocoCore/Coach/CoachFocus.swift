//
//  CoachFocus.swift
//  VocoCore
//
//  CF-1 — the pure ranking + skill-map engine behind the de-overwhelmed Coach
//  "Focus" surface. The old surface was a flat inbox of per-note `.new` cards —
//  hundreds of items, mostly the same few problems repeated, "really not usable."
//  A professional coach gives a short recap and ONE thing to work on. This file is
//  the deterministic core of that: it aggregates the dated `CoachObservation` log
//  by `(lens, patternKey)`, ranks the resulting patterns, and emits a single
//  prioritized focus (occasionally up to three) plus the five-lens skill map.
//
//  CALIBRATION — the target user already speaks English comfortably for hours a
//  day. This is a polish tool for competent speakers, not a learn-English tool, so
//  the ranking weights the lenses where a fluent speaker's next 5% lives:
//    HIGH  lexis (word choice / precision), discourse (clarity / concision),
//          prosody (fillers / pace / presence).
//    LOW   basic grammar, segmental pronunciation — surfaced only when the
//          evidence is overwhelming, never as trivia.
//  Flagging trivia to a fluent speaker is insulting and kills trust, so the
//  evidence bar is deliberately high and the lens weighting pushes a
//  high-frequency-but-low-value item (e.g. dropped articles 12×) BELOW a
//  high-value-lens item with comparable evidence (e.g. an overused filler 9×).
//
//  Everything here is a pure value type / pure function — no SwiftData, no UIKit,
//  no network — so the ranking (lens-weighting, evidence threshold, lead-with-win,
//  ordering) and the skill map are fast-testable in `swift test`. The SwiftData
//  models (`CoachObservation`) and the file-backed `LearnerProfile` are read by
//  the app and mapped onto the value types below before ranking, so the engine
//  never depends on the persistence layer.
//

import Foundation

// MARK: - Observation fact (the pure input)

/// One dated coaching finding, decoupled from the SwiftData `CoachObservation`
/// model so the ranking is testable without a model container. The app maps each
/// `CoachObservation` (LLM-lane pattern row or objective per-word GOP row) onto one
/// of these before ranking.
public struct ObservationFact: Sendable, Equatable {
    public var lens: Lens
    /// Canonical dedupe key. For LLM-lane rows this is the pattern slug; for the
    /// objective per-word GOP lane the app supplies a stable per-phoneme/word key
    /// (e.g. "gop-thorough") so repeated mispronunciations of the same word merge.
    public var key: String
    /// 1…5 impact. Objective GOP rows carry 0 from the store; the app maps a low
    /// GOP onto a severity before handing it here. Clamped into 1…5 on use.
    public var severity: Int
    /// The note's capture date — recency/trend bucket by speaking day.
    public var date: Date
    /// The learner's verbatim span, when known (LLM lane) — the evidence example.
    public var span: String?

    public init(lens: Lens, key: String, severity: Int, date: Date, span: String? = nil) {
        self.lens = lens
        self.key = key
        self.severity = severity
        self.date = date
        self.span = span
    }
}

// MARK: - Ranked focus area

/// One ranked, evidence-backed focus area: a lens + pattern key with its frequency,
/// a representative example span, the trend, and the computed priority. The top one
/// becomes "today's focus"; up to two more are the collapsed secondaries.
public struct FocusArea: Sendable, Equatable, Identifiable {
    public var lens: Lens
    public var key: String
    /// Human title — the profile pattern's `summary` when available, else the key.
    public var title: String
    /// The teachable rule, carried through from the profile pattern (drives copy +
    /// the practice drill's framing).
    public var rule: String
    /// How many times it recurred (the headline evidence — "12× this week").
    public var frequency: Int
    /// Max severity seen (1…5).
    public var severity: Int
    /// A representative verbatim example span, for the evidence line. nil for
    /// objective rows with no span.
    public var exampleSpan: String?
    /// The lens's growth-framed, evidence-grounded trend (from the skill map).
    public var trend: CoachLensTrend
    /// The composed priority score. Higher = surface sooner. Deterministic.
    public var priority: Double

    public var id: String { "\(lens.rawValue):\(key)" }

    public init(
        lens: Lens,
        key: String,
        title: String,
        rule: String,
        frequency: Int,
        severity: Int,
        exampleSpan: String?,
        trend: CoachLensTrend,
        priority: Double
    ) {
        self.lens = lens
        self.key = key
        self.title = title
        self.rule = rule
        self.frequency = frequency
        self.severity = severity
        self.exampleSpan = exampleSpan
        self.trend = trend
        self.priority = priority
    }

    /// The drill kind this focus routes to (CF-2). Convenience so the UI's
    /// one-tap Practice button maps the focus's lens straight to its drill.
    public var practiceKind: PracticeKind { PracticeKind.forLens(lens) }
}

// MARK: - Skill map entry

/// One lens in the five-lens skill map. CF-fix: the ungrounded numeric `level` is
/// gone from what the UI and the LLM see — it contradicted the data (DebugSeed put
/// grammar high while an article-drop pattern was actively recurring). What's left
/// is an honest, evidence-grounded `trend` (improving / steady / needs work) derived
/// from the lens's pattern status, plus the active-pattern count that drives it.
/// Tappable in the UI → lens detail.
public struct LensSkill: Sendable, Equatable, Identifiable {
    public var lens: Lens
    /// The growth-framed, evidence-grounded trend for this lens (CF-fix). Replaces
    /// the numeric level both on screen and in the LLM grounding block.
    public var trend: CoachLensTrend
    /// Count of patterns still actively recurring in this lens (drives the trend and
    /// a subtle "N to work on" hint without dumping the list).
    public var activeCount: Int

    public var id: Lens { lens }

    public init(lens: Lens, trend: CoachLensTrend, activeCount: Int) {
        self.lens = lens
        self.trend = trend
        self.activeCount = activeCount
    }
}

// MARK: - The de-overwhelmed surface model

/// Everything the Coach "Focus" surface renders, computed once per rollup: the
/// five-lens skill map, the prioritized focus areas (1, occasionally up to 3), and
/// the headline "win" to lead with (a recently mastered pattern, positive-leaning).
/// The flat list is NOT here — it's reached from depth ("browse all findings").
public struct CoachFocusSurface: Sendable, Equatable {
    /// The five lenses, always in `Lens.allCases` order, each with a level + trend.
    public var skillMap: [LensSkill]
    /// The prioritized focus areas, highest-priority first, already thresholded and
    /// capped. `first` is "today's focus"; the rest are collapsed secondaries.
    public var focuses: [FocusArea]
    /// A mastered pattern to celebrate as the lead win, when there is a fresh one.
    public var leadWin: RecurringPattern?

    public init(skillMap: [LensSkill], focuses: [FocusArea], leadWin: RecurringPattern?) {
        self.skillMap = skillMap
        self.focuses = focuses
        self.leadWin = leadWin
    }

    /// The single hero focus, if any cleared the evidence bar.
    public var heroFocus: FocusArea? { focuses.first }
    /// The collapsed secondary focuses (after the hero).
    public var secondaryFocuses: [FocusArea] { Array(focuses.dropFirst()) }
}

// MARK: - Ranking policy

/// The tunable knobs for ranking. Defaults are calibrated for the comfortable
/// speaker (see the file header). Pure value type so a test can dial any knob and
/// assert the ordering deterministically.
public struct FocusRankingPolicy: Sendable {
    /// Per-lens weight in the priority product. The heart of the calibration:
    /// lexis/discourse/prosody high, basic grammar/pronunciation low, so a fluent
    /// user is steered toward naturalness/precision/presence — not error drills.
    public var lensWeights: [Lens: Double]

    /// Per-lens learnability multiplier — how tractable a quick win this lens is in
    /// a single drill. Word choice and filler habits move fast; deep prosody/accent
    /// shifts are slower, so they're slightly discounted to favour momentum.
    public var learnability: [Lens: Double]

    /// Minimum recurrences before a pattern is even eligible to be surfaced as a
    /// focus. The precision bar — being sure about 1–2 beats being noisy about 30.
    public var minFrequency: Int

    /// Minimum composed priority a focus must clear to be shown at all. Above the
    /// frequency floor, this is the second gate so a fluent user is never shown
    /// trivia: a low-weight lens needs a LOT of evidence to clear it.
    public var minPriority: Double

    /// How many focuses to surface at most (1 hero + up to 2 collapsed secondaries).
    public var maxFocuses: Int

    /// A pattern that recurred within this window counts as "this week" for the
    /// recency/trend boost. Older-but-still-active patterns get a smaller weight.
    public var recentWindow: TimeInterval

    public init(
        lensWeights: [Lens: Double] = FocusRankingPolicy.defaultLensWeights,
        learnability: [Lens: Double] = FocusRankingPolicy.defaultLearnability,
        minFrequency: Int = 2,
        minPriority: Double = 6.0,
        maxFocuses: Int = 3,
        recentWindow: TimeInterval = 7 * 24 * 3600
    ) {
        self.lensWeights = lensWeights
        self.learnability = learnability
        self.minFrequency = minFrequency
        self.minPriority = minPriority
        self.maxFocuses = maxFocuses
        self.recentWindow = recentWindow
    }

    /// Lens weighting for the comfortable speaker. HIGH: lexis, discourse, prosody.
    /// LOW: grammar, pronunciation (surfaced only with overwhelming evidence).
    public static let defaultLensWeights: [Lens: Double] = [
        .lexis: 1.6,
        .discourse: 1.5,
        .prosody: 1.4,
        .grammar: 0.55,
        .pronunciation: 0.5,
    ]

    /// How quickly a single drill can move the needle per lens (favours momentum).
    public static let defaultLearnability: [Lens: Double] = [
        .lexis: 1.2,
        .discourse: 1.0,
        .prosody: 0.95,
        .grammar: 1.0,
        .pronunciation: 0.85,
    ]

    public static let `default` = FocusRankingPolicy()

    func weight(for lens: Lens) -> Double { lensWeights[lens] ?? 1.0 }
    func learnability(for lens: Lens) -> Double { learnability[lens] ?? 1.0 }
}

// MARK: - The engine

/// The pure aggregation + ranking that drives the Focus surface. Reads a
/// `LearnerProfile` (per-lens levels + `RecurringPattern`s), the dated
/// `ObservationFact` log (for frequency/severity/recency/evidence), and the
/// `CoachWeeklyRollup`s (objective trend signal), and produces a `CoachFocusSurface`.
/// Deterministic: same inputs → same surface. No persistence, no LLM, no clock —
/// `now` is injected so tests pin recency.
public enum CoachFocusEngine {

    /// Build the full surface. `facts` is the dated observation log mapped onto
    /// pure value types; `profile` supplies titles/rules/levels/wins; `weekly` is
    /// the objective rollup (unused for ranking today but threaded through so the
    /// skill map can upgrade to a real slope later without a signature change).
    public static func surface(
        facts: [ObservationFact],
        profile: LearnerProfile,
        weekly: [CoachWeeklyRollup] = [],
        now: Date,
        policy: FocusRankingPolicy = .default
    ) -> CoachFocusSurface {
        let progress = ProgressSummary.make(profile: profile, streak: StreakState())
        // CF-fix: skill-map trends are grounded in the lens's real pattern status
        // (an active pattern → "needs work"), not the ungrounded numeric level.
        let skillMap = progress.lenses.map { lens in
            LensSkill(
                lens: lens.lens,
                trend: CoachLensTrend.make(lens: lens.lens, patterns: profile.patterns),
                activeCount: lens.active)
        }

        let focuses = rank(facts: facts, profile: profile, progress: progress, now: now, policy: policy)

        // Positive-leaning: lead with a freshly-mastered pattern when there is one
        // (most recently mastered first), so the surface opens on a win.
        let leadWin = profile.patterns
            .filter { $0.status == .mastered }
            .max { $0.recency < $1.recency }

        return CoachFocusSurface(skillMap: skillMap, focuses: focuses, leadWin: leadWin)
    }

    /// Rank the observation log into prioritized focus areas. Aggregates facts by
    /// `(lens, key)`, computes `priority = frequency × severity × trend ×
    /// learnability × lensWeight`, drops anything below the frequency/priority bars,
    /// and returns the top `maxFocuses` highest-priority-first.
    ///
    /// Exposed (not private) so a test can rank a fact set directly without building
    /// a full `ProgressSummary`.
    public static func rank(
        facts: [ObservationFact],
        profile: LearnerProfile,
        progress: ProgressSummary,
        now: Date,
        policy: FocusRankingPolicy = .default
    ) -> [FocusArea] {
        // 1. Aggregate by (lens, key): frequency, max severity, latest date, a
        //    representative span (the most recent non-empty one).
        struct Agg { var lens: Lens; var key: String; var freq: Int; var sev: Int; var latest: Date; var span: String? }
        var byKey: [String: Agg] = [:]
        for fact in facts {
            let id = "\(fact.lens.rawValue):\(fact.key)"
            let sev = max(1, min(5, fact.severity))
            if var agg = byKey[id] {
                agg.freq += 1
                agg.sev = max(agg.sev, sev)
                if fact.date >= agg.latest {
                    agg.latest = fact.date
                    if let s = fact.span, !s.isEmpty { agg.span = s }
                }
                byKey[id] = agg
            } else {
                byKey[id] = Agg(lens: fact.lens, key: fact.key, freq: 1, sev: sev, latest: fact.date,
                                span: (fact.span?.isEmpty == false) ? fact.span : nil)
            }
        }

        // 2. Score each aggregate.
        let scored: [FocusArea] = byKey.values.compactMap { agg in
            guard agg.freq >= policy.minFrequency else { return nil }

            // Ranking still uses the profile's pattern-mix trend for the scoring
            // nudge; the FocusArea exposes the grounded `CoachLensTrend` for display.
            let rankTrend = progress.progress(for: agg.lens)?.trend ?? .steady
            let priority = priorityScore(
                frequency: agg.freq, severity: agg.sev, lens: agg.lens,
                latest: agg.latest, trend: rankTrend, now: now, policy: policy
            )
            guard priority >= policy.minPriority else { return nil }

            // Title/rule from the matching profile pattern when present; else the
            // key (deterministic, never blocks a focus that lacks a profile row).
            let pattern = profile.patterns.first { $0.lens == agg.lens && $0.key == agg.key }
            let title = pattern?.summary ?? agg.key
            let rule = pattern?.rule ?? ""
            let span = agg.span ?? pattern?.examples.last?.span

            return FocusArea(
                lens: agg.lens, key: agg.key, title: title, rule: rule,
                frequency: agg.freq, severity: agg.sev, exampleSpan: span,
                trend: CoachLensTrend.make(lens: agg.lens, patterns: profile.patterns),
                priority: priority
            )
        }

        // 3. Highest priority first; ties broken deterministically by frequency
        //    then id, so the ordering is stable/diffable across runs.
        let ordered = scored.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            if a.frequency != b.frequency { return a.frequency > b.frequency }
            return a.id < b.id
        }
        return Array(ordered.prefix(policy.maxFocuses))
    }

    /// The priority product. Severity and frequency are dampened (sqrt / log) so a
    /// runaway count in a low-value lens can't swamp the lens weighting — the whole
    /// point of the calibration. A recent recurrence (within `recentWindow`) and an
    /// improving/steady trend nudge the score; a mastered-leaning lens is de-emphasized.
    static func priorityScore(
        frequency: Int,
        severity: Int,
        lens: Lens,
        latest: Date,
        trend: ProgressSummary.Trend,
        now: Date,
        policy: FocusRankingPolicy
    ) -> Double {
        // Frequency: log-dampened so 12× isn't 6× as strong as 2× — evidence past a
        // point is "yes, this is real", not linearly more urgent.
        let freqTerm = log2(Double(frequency) + 1)            // 2→1.58, 9→3.32, 12→3.70
        // Severity: mild, sqrt-dampened (1→1.0 … 5→2.24).
        let sevTerm = (Double(max(1, min(5, severity))).squareRoot())
        // Recency: a within-window recurrence is "this week" (full weight); older
        // active patterns decay toward a floor so stale habits don't lead.
        let age = max(0, now.timeIntervalSince(latest))
        let recencyTerm = age <= policy.recentWindow
            ? 1.0
            : max(0.5, 1.0 - (age - policy.recentWindow) / (policy.recentWindow * 4))
        // Trend: an improving lens still deserves a nudge of attention but less than
        // a steady/regressing one; a brand-new lens is neutral.
        let trendTerm: Double = {
            switch trend {
            case .improving: return 0.85
            case .steady: return 1.0
            case .new: return 1.0
            }
        }()

        return freqTerm
            * sevTerm
            * recencyTerm
            * trendTerm
            * policy.learnability(for: lens)
            * policy.weight(for: lens)
    }
}
