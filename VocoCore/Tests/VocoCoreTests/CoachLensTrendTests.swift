import Foundation
import Testing
@testable import VocoCore

/// CF-fix — the per-lens trend that replaces the ungrounded numeric level. The
/// load-bearing case: a lens with an ACTIVE pattern reads "needs work", never high.
struct CoachLensTrendTests {

    private func pattern(_ lens: Lens, _ key: String, _ status: PatternStatus) -> RecurringPattern {
        RecurringPattern(
            lens: lens, key: key, summary: key, rule: "",
            frequency: 3, firstSeen: Date(timeIntervalSince1970: 0),
            recency: Date(timeIntervalSince1970: 1_000_000), status: status)
    }

    @Test
    func activePatternMakesLensNeedWork() {
        let trend = CoachLensTrend.make(lens: .grammar, patterns: [pattern(.grammar, "drop-articles", .active)])
        #expect(trend == .needsWork)
    }

    @Test
    func masteredPatternMakesLensImproving() {
        let trend = CoachLensTrend.make(lens: .prosody, patterns: [pattern(.prosody, "fillers", .mastered)])
        #expect(trend == .improving)
    }

    @Test
    func improvingPatternMakesLensImproving() {
        let trend = CoachLensTrend.make(lens: .discourse, patterns: [pattern(.discourse, "tighten", .improving)])
        #expect(trend == .improving)
    }

    @Test
    func noPatternsIsSteadyNotNegative() {
        let trend = CoachLensTrend.make(lens: .lexis, patterns: [])
        #expect(trend == .steady)
    }

    @Test
    func activeDominatesAWinInTheSameLens() {
        // A lens with BOTH a win and a still-active pattern must read "needs work":
        // there is something live to drill, so we don't soften it to "improving".
        let patterns = [
            pattern(.grammar, "drop-articles", .active),
            pattern(.grammar, "old-tense-slip", .mastered),
        ]
        #expect(CoachLensTrend.make(lens: .grammar, patterns: patterns) == .needsWork)
    }

    @Test
    func onlyConsidersThisLensesPatterns() {
        // An active pattern in ANOTHER lens must not bleed into this lens's trend.
        let patterns = [pattern(.lexis, "overuse", .active)]
        #expect(CoachLensTrend.make(lens: .grammar, patterns: patterns) == .steady)
    }
}
