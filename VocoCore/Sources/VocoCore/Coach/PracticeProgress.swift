//
//  PracticeProgress.swift
//  VocoCore
//
//  CF-3 — the progress & accumulation loop. Practice used to be recorded but never
//  surfaced, so there was no proof it was working and no reason to come back. This
//  file is the PURE, deterministic core of two things a professional coaching tool
//  lives or dies on:
//
//    1. Visible accumulation — "today / this week you practiced X": reps grouped by
//       lens/focus, with the improvement delta (the closed-loop score from the
//       shadow GOP / word-swap judge). `PracticeLog.summary` builds it.
//    2. Proof it's working — for a focus area, the per-`patternKey` occurrence trend
//       over the dated `CoachObservation` log, with practice events overlaid, so the
//       surface can say *"you practiced this 3× → it fell from 12 to 7."* This is the
//       CT-1 / CT-2 trend work, folded in and made purposeful. `FrequencyTrend.make`
//       builds it, and — critically — it is HONEST: it only claims an improvement
//       when the drop is real over enough data (the same evidence discipline as CF-1),
//       never declaring victory on noise.
//
//  CALIBRATION — the target user already speaks English comfortably (see CF-1). So
//  everything here is framed as REFINEMENT, not remediation: a higher score is "more
//  natural / more direct", a frequency drop is "below your earlier baseline", never
//  "errors fixed". Nothing decreases punitively — accumulation is growth-only.
//
//  Everything is a pure value type / pure function — no SwiftData, no UIKit, no
//  network, no ambient clock (`now` is injected) — so the aggregation, the deltas,
//  and the "don't claim improvement on noise" guard are all fast-testable in
//  `swift test`. The app maps its persisted `PracticeAttempt` rows and dated
//  `CoachObservation`s onto the pure facts below before calling in.
//

import Foundation

// MARK: - Practice attempt fact (the pure input)

/// One recorded practice attempt, decoupled from the SwiftData `PracticeAttempt` /
/// `PracticeItem` models so the aggregation is testable without a model container.
/// The app maps each persisted attempt (plus its parent item's CF-3 tags) onto one
/// of these.
public struct PracticeAttemptFact: Sendable, Equatable {
    /// When the attempt happened.
    public var date: Date
    /// Which drill it was (CF-2). `shadow` vs `wordSwap` drives how the score reads.
    public var kind: PracticeKind
    /// The focus area's lens, when the drill was launched from a focus / coach card
    /// (CF-3 tagging). nil for an untagged pasted-text drill.
    public var lens: Lens?
    /// The focus area's pattern key, when tagged. Pairs with `lens` so a run of
    /// attempts is attributable to a single `(lens, patternKey)` focus.
    public var patternKey: String?
    /// The attempt's overall quality in 0…1 (mean of the per-segment ASR-match
    /// scores for a shadow drill; the single word-swap judge score otherwise). This
    /// is the "how natural / how close to the target" signal, never a grade.
    public var score: Double
    /// Closed-loop pronunciation improvement vs the previous attempt of the same
    /// item, when a comparison existed (shadow drills with a GOP model). Positive =
    /// pronunciation got closer to native. nil otherwise.
    public var gopDelta: Double?

    public init(
        date: Date,
        kind: PracticeKind,
        lens: Lens? = nil,
        patternKey: String? = nil,
        score: Double,
        gopDelta: Double? = nil
    ) {
        self.date = date
        self.kind = kind
        self.lens = lens
        self.patternKey = patternKey
        self.score = score
        self.gopDelta = gopDelta
    }
}

// MARK: - Per-lens practice roll-up

/// How much practice landed on one lens in the accumulation window, plus the
/// growth-framed improvement delta. Drives a single row in the "today / this week
/// you practiced" strip.
public struct LensPracticeReps: Sendable, Equatable, Identifiable {
    public var lens: Lens
    /// Reps in the window (attempts on this lens).
    public var reps: Int
    /// Mean attempt score in the window (0…1) — "how natural it's landing now".
    public var meanScore: Double
    /// Improvement delta in the window: the mean of the most recent attempts minus
    /// the mean of the earliest, in 0…1 score points. Positive = more natural / more
    /// on-target than when you started. nil when there aren't enough attempts to
    /// compare honestly (a single rep can't show a delta).
    public var scoreDelta: Double?
    /// The summed closed-loop GOP improvement across this lens's attempts (shadow
    /// drills only), when any attempt carried a comparison. Positive = pronunciation
    /// moved toward native. nil when no attempt had a GOP delta.
    public var gopDelta: Double?

    public var id: Lens { lens }

    public init(
        lens: Lens,
        reps: Int,
        meanScore: Double,
        scoreDelta: Double? = nil,
        gopDelta: Double? = nil
    ) {
        self.lens = lens
        self.reps = reps
        self.meanScore = meanScore
        self.scoreDelta = scoreDelta
        self.gopDelta = gopDelta
    }
}

/// Everything the "today / this week you practiced" strip renders, computed purely
/// from the practice-attempt facts. Empty (`isEmpty`) when nothing was practiced in
/// the window, so the strip can hide rather than show a hollow zero.
public struct PracticeSummary: Sendable, Equatable {
    /// Total reps today (calendar day of `now`).
    public var repsToday: Int
    /// Total reps this week (rolling 7-day window ending at `now`).
    public var repsThisWeek: Int
    /// Per-lens reps this week, most-practiced first (drives the strip's rows). Only
    /// lenses with at least one rep appear.
    public var byLens: [LensPracticeReps]
    /// The single most-practiced lens this week, if any — the headline.
    public var topLens: LensPracticeReps? { byLens.first }

    public init(repsToday: Int, repsThisWeek: Int, byLens: [LensPracticeReps]) {
        self.repsToday = repsToday
        self.repsThisWeek = repsThisWeek
        self.byLens = byLens
    }

    /// True when nothing was practiced in the week — the strip hides.
    public var isEmpty: Bool { repsThisWeek == 0 }
}

// MARK: - Practice-log aggregation

/// The pure aggregation behind the accumulation strip. Reads the dated
/// practice-attempt facts and rolls them up into today/week reps grouped by lens,
/// each with a growth-framed improvement delta. Deterministic: same facts + `now`
/// in → same summary out. No persistence, no clock — `now` is injected.
public enum PracticeLog {

    /// The rolling window that counts as "this week". A rolling 7 days (not a
    /// calendar week) so the strip is stable across weekday boundaries — the issue
    /// recommends a weekly headline + daily reps.
    public static let weekWindow: TimeInterval = 7 * 24 * 3600

    /// Build the accumulation summary from the attempt facts.
    ///
    /// - Parameters:
    ///   - facts: the dated practice attempts (mapped from `PracticeAttempt` +
    ///     parent item tags). Order-independent.
    ///   - now: the reference instant (today / week are measured back from here).
    ///   - calendar: for the "today" calendar-day bucket; injected for tests.
    public static func summary(
        facts: [PracticeAttemptFact],
        now: Date,
        calendar: Calendar = .current
    ) -> PracticeSummary {
        let today = calendar.startOfDay(for: now)
        let weekStart = now.addingTimeInterval(-weekWindow)

        let inWeek = facts.filter { $0.date > weekStart && $0.date <= now }
        let repsToday = inWeek.filter { calendar.startOfDay(for: $0.date) == today }.count

        // Group the week's attempts by lens. Attempts with no lens tag (untagged
        // pasted-text drills) still count toward the totals, but can't be attributed
        // to a lens row — so they're folded into the totals only, not `byLens`.
        var byLens: [Lens: [PracticeAttemptFact]] = [:]
        for fact in inWeek {
            guard let lens = fact.lens else { continue }
            byLens[lens, default: []].append(fact)
        }

        let rows: [LensPracticeReps] = byLens.map { lens, attempts in
            let sorted = attempts.sorted { $0.date < $1.date }
            let scores = sorted.map(\.score)
            let meanScore = mean(scores)
            let scoreDelta = improvementDelta(scores)

            // Sum the closed-loop GOP improvements across the lens's attempts.
            let gopDeltas = sorted.compactMap(\.gopDelta)
            let gopDelta = gopDeltas.isEmpty ? nil : gopDeltas.reduce(0, +)

            return LensPracticeReps(
                lens: lens,
                reps: attempts.count,
                meanScore: meanScore,
                scoreDelta: scoreDelta,
                gopDelta: gopDelta
            )
        }
        // Most-practiced first; ties broken by lens raw value for a stable order.
        .sorted { ($0.reps, $1.lens.rawValue) > ($1.reps, $0.lens.rawValue) }

        return PracticeSummary(repsToday: repsToday, repsThisWeek: inWeek.count, byLens: rows)
    }

    // MARK: Math (the only place arithmetic happens)

    /// The growth-framed improvement delta over a chronological score series: the
    /// mean of the most recent half minus the mean of the earliest half. Returns nil
    /// for fewer than two attempts (a single rep can't show movement). Splitting into
    /// halves (rather than last-minus-first) damps single-attempt noise so one lucky
    /// or unlucky rep doesn't read as a trend.
    static func improvementDelta(_ scores: [Double]) -> Double? {
        guard scores.count >= 2 else { return nil }
        let mid = scores.count / 2
        let early = Array(scores.prefix(mid))
        let recent = Array(scores.suffix(scores.count - mid))
        return mean(recent) - mean(early)
    }

    static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }
}

// MARK: - Per-focus frequency trend (the practice→drop signal)

/// One dated bucket of how often a focus area's pattern occurred, with how many
/// times it was practiced in the same bucket overlaid. The series of these is what
/// the closing-the-loop chart plots.
public struct FrequencyBucket: Sendable, Equatable, Identifiable {
    /// Start-of-day (or start-of-week) for this bucket.
    public var periodStart: Date
    /// How many times the pattern was OBSERVED in this period.
    public var occurrences: Int
    /// How many times it was PRACTICED in this period (the overlay).
    public var practiceReps: Int

    public var id: Date { periodStart }

    public init(periodStart: Date, occurrences: Int, practiceReps: Int) {
        self.periodStart = periodStart
        self.occurrences = occurrences
        self.practiceReps = practiceReps
    }
}

/// The verdict on whether practicing a focus area genuinely reduced its frequency.
/// Deliberately conservative: `improved` is reserved for a real, sustained drop over
/// enough data; everything short of that reads as honest, non-punitive holding.
public enum FrequencyVerdict: String, Sendable, Equatable {
    /// The pattern's frequency genuinely fell after practice, over enough data — the
    /// motivating "it's working" state. Only this one makes the surface claim a win.
    case improved
    /// Practiced, and the frequency is holding steady — honest, not a failure. (A
    /// fluent speaker's habit not getting worse is itself fine.)
    case steady
    /// Not enough data yet to claim anything either way — keep practicing. The
    /// default until the evidence bar clears, so the surface never over-claims.
    case tooEarly
}

/// The full practice→frequency-drop signal for one focus area: its bucketed
/// occurrence trend with practice overlaid, the early-vs-recent occurrence counts
/// that back the headline ("12 → 7"), the total reps, and the honest verdict.
public struct FrequencyTrend: Sendable, Equatable {
    public var lens: Lens
    public var patternKey: String
    /// The occurrence/practice buckets, oldest first.
    public var buckets: [FrequencyBucket]
    /// Mean occurrences per active period BEFORE the learner started practicing this
    /// pattern (the baseline). The "12" in "12 → 7", on a per-period basis.
    public var baselineOccurrences: Int
    /// Mean occurrences per active period AFTER practice began. The "7".
    public var recentOccurrences: Int
    /// Total times this pattern was practiced across the window.
    public var totalReps: Int
    /// The honest verdict — only `.improved` lets the surface claim the drop.
    public var verdict: FrequencyVerdict

    public init(
        lens: Lens,
        patternKey: String,
        buckets: [FrequencyBucket],
        baselineOccurrences: Int,
        recentOccurrences: Int,
        totalReps: Int,
        verdict: FrequencyVerdict
    ) {
        self.lens = lens
        self.patternKey = patternKey
        self.buckets = buckets
        self.baselineOccurrences = baselineOccurrences
        self.recentOccurrences = recentOccurrences
        self.totalReps = totalReps
        self.verdict = verdict
    }

    /// Convenience: whether the surface may say "it's working" (i.e. claim the drop).
    public var didImprove: Bool { verdict == .improved }
}

/// Thresholds for the practice→frequency-drop signal. The whole point is honesty,
/// so the defaults are conservative — declaring victory on noise is worse than
/// staying quiet. Pure value type so a test can dial any knob.
public struct FrequencyTrendPolicy: Sendable {
    /// How a period is bucketed for the trend chart.
    public var bucket: Calendar.Component
    /// Minimum practice reps before a `.improved` verdict is even considered. Below
    /// this you haven't practiced enough to attribute any change to practice.
    public var minReps: Int
    /// Minimum total observations across the window before a verdict beyond
    /// `.tooEarly` is allowed — too few occurrences and any "drop" is just sampling.
    public var minObservations: Int
    /// The relative drop (baseline → recent) required to claim `.improved`. 0.25 =
    /// recent must be at least 25% below baseline. A real, visible reduction, not
    /// a one-occurrence wobble.
    public var minRelativeDrop: Double
    /// The whole analysis window — observations older than this are ignored so the
    /// baseline reflects recent speaking, not ancient history.
    public var window: TimeInterval

    public init(
        bucket: Calendar.Component = .day,
        minReps: Int = 2,
        minObservations: Int = 6,
        minRelativeDrop: Double = 0.25,
        window: TimeInterval = 60 * 24 * 3600
    ) {
        self.bucket = bucket
        self.minReps = minReps
        self.minObservations = minObservations
        self.minRelativeDrop = minRelativeDrop
        self.window = window
    }

    public static let `default` = FrequencyTrendPolicy()
}

public extension FrequencyTrend {

    /// Build the practice→frequency-drop signal for a single focus area.
    ///
    /// The split point is the learner's FIRST practice rep for this pattern: the
    /// "before" baseline is the mean occurrences/period up to that point; the "after"
    /// is the mean occurrences/period since. Practicing a pattern then seeing its
    /// per-period occurrences fall below the baseline is the closed loop.
    ///
    /// HONESTY GUARD — `.improved` requires ALL of:
    ///   * at least `minReps` practice reps (you practiced it enough to attribute),
    ///   * at least `minObservations` total occurrences (enough signal to trust),
    ///   * a recent mean at least `minRelativeDrop` below the baseline mean,
    ///   * AND a baseline period existing at all (you can't have "dropped from"
    ///     nothing).
    /// Anything short of that is `.steady` (practiced, holding) or `.tooEarly` (not
    /// enough data) — never a false "it's working".
    ///
    /// - Parameters:
    ///   - lens / patternKey: the focus area to analyze.
    ///   - observations: the dated `ObservationFact` log (CF-1's pure input), already
    ///     filtered to this `(lens, key)` OR the full log (this filters internally).
    ///   - practiceFacts: the dated practice attempts (this filters to the matching
    ///     `(lens, patternKey)` internally).
    ///   - now: the reference instant.
    static func make(
        lens: Lens,
        patternKey: String,
        observations: [ObservationFact],
        practiceFacts: [PracticeAttemptFact],
        now: Date,
        policy: FrequencyTrendPolicy = .default,
        calendar: Calendar = .current
    ) -> FrequencyTrend {
        let windowStart = now.addingTimeInterval(-policy.window)

        // Filter to this focus area, within the window.
        let obs = observations
            .filter { $0.lens == lens && $0.key == patternKey && $0.date > windowStart && $0.date <= now }
            .sorted { $0.date < $1.date }
        let reps = practiceFacts
            .filter { $0.lens == lens && $0.patternKey == patternKey && $0.date > windowStart && $0.date <= now }
            .sorted { $0.date < $1.date }

        // Bucket occurrences + practice reps by period for the chart.
        let buckets = bucketed(obs: obs, reps: reps, policy: policy, calendar: calendar)

        // The split: the learner's first practice rep for this pattern. With no reps
        // there's no "after", so the whole series is baseline and the verdict is
        // `.tooEarly`.
        guard let firstRepDate = reps.first?.date else {
            let baseline = perPeriodMean(obs.map(\.date), policy: policy, calendar: calendar)
            return FrequencyTrend(
                lens: lens, patternKey: patternKey, buckets: buckets,
                baselineOccurrences: baseline, recentOccurrences: baseline,
                totalReps: 0, verdict: .tooEarly
            )
        }

        let before = obs.filter { $0.date < firstRepDate }
        let after = obs.filter { $0.date >= firstRepDate }
        let baselineMean = perPeriodMean(before.map(\.date), policy: policy, calendar: calendar)
        let recentMean = perPeriodMean(after.map(\.date), policy: policy, calendar: calendar)

        let verdict = self.verdict(
            totalObservations: obs.count,
            totalReps: reps.count,
            baselineMean: baselineMean,
            recentMean: recentMean,
            hadBaselinePeriod: !before.isEmpty,
            policy: policy
        )

        return FrequencyTrend(
            lens: lens, patternKey: patternKey, buckets: buckets,
            baselineOccurrences: baselineMean, recentOccurrences: recentMean,
            totalReps: reps.count, verdict: verdict
        )
    }

    /// The honesty gate. Pure + exposed so a test can pin the "don't claim
    /// improvement on noise" boundary directly.
    static func verdict(
        totalObservations: Int,
        totalReps: Int,
        baselineMean: Int,
        recentMean: Int,
        hadBaselinePeriod: Bool,
        policy: FrequencyTrendPolicy = .default
    ) -> FrequencyVerdict {
        // Not enough signal at all → never claim anything.
        guard totalReps >= policy.minReps,
              totalObservations >= policy.minObservations,
              hadBaselinePeriod, baselineMean > 0
        else { return .tooEarly }

        let drop = Double(baselineMean - recentMean) / Double(baselineMean)
        if drop >= policy.minRelativeDrop { return .improved }
        return .steady
    }

    // MARK: Bucketing

    private static func bucketed(
        obs: [ObservationFact],
        reps: [PracticeAttemptFact],
        policy: FrequencyTrendPolicy,
        calendar: Calendar
    ) -> [FrequencyBucket] {
        func periodStart(_ date: Date) -> Date {
            switch policy.bucket {
            case .weekOfYear:
                let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
            default:
                return calendar.startOfDay(for: date)
            }
        }

        var occ: [Date: Int] = [:]
        for o in obs { occ[periodStart(o.date), default: 0] += 1 }
        var prac: [Date: Int] = [:]
        for r in reps { prac[periodStart(r.date), default: 0] += 1 }

        let periods = Set(occ.keys).union(prac.keys).sorted()
        return periods.map { p in
            FrequencyBucket(periodStart: p, occurrences: occ[p] ?? 0, practiceReps: prac[p] ?? 0)
        }
    }

    /// Mean occurrences per ACTIVE period (a period in which the pattern occurred at
    /// least once). Per-active-period (not per-calendar-period) so a sparse speaker
    /// isn't penalized for not speaking every day — the baseline reflects how often
    /// the pattern shows up WHEN they speak, which is what practice can move.
    /// Rounded to the nearest whole occurrence for the "12 → 7" headline.
    private static func perPeriodMean(
        _ dates: [Date],
        policy: FrequencyTrendPolicy,
        calendar: Calendar
    ) -> Int {
        guard !dates.isEmpty else { return 0 }
        func periodStart(_ date: Date) -> Date {
            switch policy.bucket {
            case .weekOfYear:
                let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
            default:
                return calendar.startOfDay(for: date)
            }
        }
        var perPeriod: [Date: Int] = [:]
        for d in dates { perPeriod[periodStart(d), default: 0] += 1 }
        let counts = perPeriod.values
        let mean = Double(counts.reduce(0, +)) / Double(counts.count)
        return Int(mean.rounded())
    }
}
