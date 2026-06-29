//
//  PracticeProgressTests.swift
//  VocoCoreTests
//
//  CF-3 — the pure practice-log aggregation + the per-pattern frequency-drop signal,
//  including the "don't claim improvement on noise" honesty guard.
//

import Foundation
import Testing
@testable import VocoCore

@Suite("CF-3 practice accumulation + progress loop")
struct PracticeProgressTests {

    // A fixed reference instant so day/week buckets are deterministic.
    let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 ~22:13 UTC
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 24 * 3600) }

    func attempt(_ days: Double, lens: Lens?, key: String? = nil, score: Double, gop: Double? = nil, kind: PracticeKind = .shadow) -> PracticeAttemptFact {
        PracticeAttemptFact(date: ago(days), kind: kind, lens: lens, patternKey: key, score: score, gopDelta: gop)
    }

    func obs(_ days: Double, lens: Lens, key: String) -> ObservationFact {
        ObservationFact(lens: lens, key: key, severity: 3, date: ago(days))
    }

    // MARK: - Practice-log aggregation

    @Test("reps bucket into today vs this week")
    func repsTodayAndWeek() {
        let facts = [
            attempt(0, lens: .lexis, score: 0.8),    // today
            attempt(0.2, lens: .lexis, score: 0.7),  // today (earlier)
            attempt(2, lens: .prosody, score: 0.6),  // this week, not today
            attempt(9, lens: .grammar, score: 0.5),  // outside the 7-day window
        ]
        let s = PracticeLog.summary(facts: facts, now: now, calendar: cal)
        #expect(s.repsToday == 2)
        #expect(s.repsThisWeek == 3)
        #expect(!s.isEmpty)
    }

    @Test("empty when nothing practiced in the week")
    func emptyWeek() {
        let s = PracticeLog.summary(facts: [attempt(30, lens: .lexis, score: 0.8)], now: now, calendar: cal)
        #expect(s.isEmpty)
        #expect(s.repsThisWeek == 0)
        #expect(s.byLens.isEmpty)
    }

    @Test("reps group by lens, most-practiced first")
    func groupByLens() {
        let facts = [
            attempt(0, lens: .lexis, score: 0.8),
            attempt(1, lens: .lexis, score: 0.9),
            attempt(2, lens: .lexis, score: 0.7),
            attempt(0, lens: .prosody, score: 0.6),
        ]
        let s = PracticeLog.summary(facts: facts, now: now, calendar: cal)
        #expect(s.byLens.count == 2)
        #expect(s.topLens?.lens == .lexis)
        #expect(s.topLens?.reps == 3)
        #expect(s.byLens.last?.lens == .prosody)
    }

    @Test("untagged attempts count toward totals but not lens rows")
    func untaggedFoldIntoTotals() {
        let facts = [
            attempt(0, lens: nil, score: 0.8),       // pasted-text drill, no lens
            attempt(1, lens: .lexis, score: 0.9),
        ]
        let s = PracticeLog.summary(facts: facts, now: now, calendar: cal)
        #expect(s.repsThisWeek == 2)
        #expect(s.byLens.count == 1)               // only the lexis attempt is attributable
        #expect(s.byLens.first?.lens == .lexis)
    }

    @Test("improvement delta is recent-half minus early-half, growth-framed")
    func improvementDelta() {
        // Scores rising over the week → positive delta (more natural than at the start).
        let facts = [
            attempt(4, lens: .lexis, score: 0.5),
            attempt(3, lens: .lexis, score: 0.6),
            attempt(1, lens: .lexis, score: 0.8),
            attempt(0, lens: .lexis, score: 0.9),
        ]
        let s = PracticeLog.summary(facts: facts, now: now, calendar: cal)
        let row = s.byLens.first!
        #expect(row.scoreDelta != nil)
        #expect(row.scoreDelta! > 0)   // improved
    }

    @Test("single rep yields no delta (can't show movement)")
    func singleRepNoDelta() {
        let s = PracticeLog.summary(facts: [attempt(0, lens: .lexis, score: 0.8)], now: now, calendar: cal)
        #expect(s.byLens.first?.scoreDelta == nil)
    }

    @Test("GOP deltas sum across a lens's attempts; nil when none carry one")
    func gopDeltaSums() {
        let withGop = [
            attempt(2, lens: .pronunciation, score: 0.7, gop: 0.3),
            attempt(0, lens: .pronunciation, score: 0.8, gop: 0.4),
        ]
        let s1 = PracticeLog.summary(facts: withGop, now: now, calendar: cal)
        #expect(s1.byLens.first?.gopDelta == 0.7)

        let noGop = [attempt(0, lens: .pronunciation, score: 0.7), attempt(1, lens: .pronunciation, score: 0.8)]
        let s2 = PracticeLog.summary(facts: noGop, now: now, calendar: cal)
        #expect(s2.byLens.first?.gopDelta == nil)
    }

    // MARK: - Frequency trend (the practice→drop signal)

    @Test("genuine drop after practice is reported as improved")
    func genuineDrop() {
        // Baseline: heavy occurrences before practice; after the first rep, occurrences fall.
        var observations: [ObservationFact] = []
        // Before practice (days 30…16): ~3 occurrences/day.
        for day in stride(from: 30.0, through: 16.0, by: -1) {
            for _ in 0..<3 { observations.append(obs(day, lens: .grammar, key: "drop-articles")) }
        }
        // After practice (days 10…0): ~1 occurrence/day.
        for day in stride(from: 10.0, through: 0.0, by: -1) {
            observations.append(obs(day, lens: .grammar, key: "drop-articles"))
        }
        let reps = [
            attempt(12, lens: .grammar, key: "drop-articles", score: 0.7),
            attempt(8, lens: .grammar, key: "drop-articles", score: 0.8),
            attempt(4, lens: .grammar, key: "drop-articles", score: 0.85),
        ]
        let trend = FrequencyTrend.make(
            lens: .grammar, patternKey: "drop-articles",
            observations: observations, practiceFacts: reps, now: now, calendar: cal
        )
        #expect(trend.verdict == .improved)
        #expect(trend.didImprove)
        #expect(trend.baselineOccurrences > trend.recentOccurrences)
        #expect(trend.totalReps == 3)
        #expect(!trend.buckets.isEmpty)
    }

    @Test("no practice → tooEarly, never a claim")
    func noPracticeTooEarly() {
        var observations: [ObservationFact] = []
        for day in stride(from: 20.0, through: 0.0, by: -1) {
            observations.append(obs(day, lens: .grammar, key: "drop-articles"))
        }
        let trend = FrequencyTrend.make(
            lens: .grammar, patternKey: "drop-articles",
            observations: observations, practiceFacts: [], now: now, calendar: cal
        )
        #expect(trend.verdict == .tooEarly)
        #expect(!trend.didImprove)
    }

    @Test("HONESTY GUARD: a tiny sample never claims improvement (noise)")
    func noiseDoesNotClaimImprovement() {
        // Only 3 total occurrences and a single rep — far below the evidence bar.
        // Even though "recent" happens to be lower, we must NOT declare victory.
        let observations = [
            obs(20, lens: .lexis, key: "overuse-basically"),
            obs(18, lens: .lexis, key: "overuse-basically"),
            obs(2, lens: .lexis, key: "overuse-basically"),
        ]
        let reps = [attempt(10, lens: .lexis, key: "overuse-basically", score: 0.8)]
        let trend = FrequencyTrend.make(
            lens: .lexis, patternKey: "overuse-basically",
            observations: observations, practiceFacts: reps, now: now, calendar: cal
        )
        #expect(trend.verdict == .tooEarly)   // < minReps and < minObservations
        #expect(!trend.didImprove)
    }

    @Test("practiced but frequency holding → steady, not a false win")
    func holdingSteady() {
        // Plenty of evidence + reps, but occurrences are flat before/after practice.
        var observations: [ObservationFact] = []
        for day in stride(from: 30.0, through: 0.0, by: -2) {
            for _ in 0..<2 { observations.append(obs(day, lens: .prosody, key: "rushed-pacing")) }
        }
        let reps = [
            attempt(14, lens: .prosody, key: "rushed-pacing", score: 0.6),
            attempt(7, lens: .prosody, key: "rushed-pacing", score: 0.6),
        ]
        let trend = FrequencyTrend.make(
            lens: .prosody, patternKey: "rushed-pacing",
            observations: observations, practiceFacts: reps, now: now, calendar: cal
        )
        #expect(trend.verdict == .steady)
        #expect(!trend.didImprove)
    }

    @Test("seed-shaped data: overuse-basically reads as improved (runtime proof)")
    func seedShapedImproves() {
        // Mirrors DebugSeed exactly: heavy `overuse-basically` occurrences BEFORE the
        // first practice rep (day 14), sparse AFTER, with 5 reps across the window.
        // Locks the "It's working" card that the seeded simulator run renders.
        var observations: [ObservationFact] = []
        for day in stride(from: 30, through: 16, by: -2) {         // before: 3/active-day
            for _ in 0..<3 { observations.append(obs(Double(day), lens: .lexis, key: "overuse-basically")) }
        }
        for day in stride(from: 10, through: 0, by: -2) {          // after: 1/active-day
            observations.append(obs(Double(day), lens: .lexis, key: "overuse-basically"))
        }
        let reps = [14, 12, 8, 4, 0].map { attempt(Double($0), lens: .lexis, key: "overuse-basically", score: 0.7, kind: .wordSwap) }
        let trend = FrequencyTrend.make(
            lens: .lexis, patternKey: "overuse-basically",
            observations: observations, practiceFacts: reps, now: now, calendar: cal
        )
        #expect(trend.verdict == .improved)
        #expect(trend.totalReps == 5)
        #expect(trend.baselineOccurrences > trend.recentOccurrences)   // a real "X → Y" drop
    }

    @Test("verdict gate: relative drop below threshold is steady, at/above is improved")
    func verdictGateBoundary() {
        // 8 obs, 3 reps, baseline 10. A 10% drop (→9) is below the 25% bar → steady.
        let steady = FrequencyTrend.verdict(
            totalObservations: 8, totalReps: 3, baselineMean: 10, recentMean: 9, hadBaselinePeriod: true
        )
        #expect(steady == .steady)
        // A 30% drop (→7) clears the bar → improved.
        let improved = FrequencyTrend.verdict(
            totalObservations: 8, totalReps: 3, baselineMean: 10, recentMean: 7, hadBaselinePeriod: true
        )
        #expect(improved == .improved)
        // No baseline period → can't have "dropped from" nothing → tooEarly.
        let noBaseline = FrequencyTrend.verdict(
            totalObservations: 8, totalReps: 3, baselineMean: 0, recentMean: 0, hadBaselinePeriod: false
        )
        #expect(noBaseline == .tooEarly)
    }
}
