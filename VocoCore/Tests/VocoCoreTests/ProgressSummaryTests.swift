import Foundation
import Testing
@testable import VocoCore

/// CI-12: the pure cross-lens progress roll-up. Deterministic, derived only from
/// already-persisted inputs (profile + streak + per-note pronunciation signals).
struct ProgressSummaryTests {

    private let day0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func pattern(
        _ lens: Lens,
        key: String,
        status: PatternStatus,
        frequency: Int = 1
    ) -> RecurringPattern {
        RecurringPattern(
            lens: lens, key: key, summary: "summary \(key)", rule: "rule",
            frequency: frequency, firstSeen: day0, recency: day0, status: status
        )
    }

    // MARK: - Per-lens roll-up

    @Test
    func everyLensHasARowInOrder() {
        let summary = ProgressSummary.make(profile: LearnerProfile(), streak: StreakState())
        #expect(summary.lenses.map(\.lens) == Lens.allCases)
    }

    @Test
    func levelsCarryThroughFromProfile() {
        var profile = LearnerProfile()
        profile.levels = [.grammar: 42, .pronunciation: 17]
        let summary = ProgressSummary.make(profile: profile, streak: StreakState())
        #expect(summary.progress(for: .grammar)?.level == 42)
        #expect(summary.progress(for: .pronunciation)?.level == 17)
        // A lens with no stored level reports 0.
        #expect(summary.progress(for: .lexis)?.level == 0)
    }

    @Test
    func countsPatternsByStatusPerLens() {
        var profile = LearnerProfile()
        profile.patterns = [
            pattern(.grammar, key: "a", status: .active),
            pattern(.grammar, key: "b", status: .improving),
            pattern(.grammar, key: "c", status: .mastered),
            pattern(.grammar, key: "d", status: .mastered),
            pattern(.lexis, key: "e", status: .active),
        ]
        let summary = ProgressSummary.make(profile: profile, streak: StreakState())
        let grammar = summary.progress(for: .grammar)!
        #expect(grammar.active == 1)
        #expect(grammar.improving == 1)
        #expect(grammar.mastered == 2)
        let lexis = summary.progress(for: .lexis)!
        #expect(lexis.active == 1)
        #expect(lexis.mastered == 0)
    }

    @Test
    func totalWinsSumsMasteredAcrossLenses() {
        var profile = LearnerProfile()
        profile.patterns = [
            pattern(.grammar, key: "a", status: .mastered),
            pattern(.lexis, key: "b", status: .mastered),
            pattern(.discourse, key: "c", status: .active),
        ]
        let summary = ProgressSummary.make(profile: profile, streak: StreakState())
        #expect(summary.totalWins == 2)
    }

    // MARK: - Trend (growth-framed)

    @Test
    func newLensWithNoLevelAndNoPatternsIsNew() {
        let summary = ProgressSummary.make(profile: LearnerProfile(), streak: StreakState())
        #expect(summary.progress(for: .grammar)?.trend == .new)
    }

    @Test
    func masteredOrImprovingPatternsReadAsImproving() {
        var profile = LearnerProfile()
        profile.patterns = [
            pattern(.grammar, key: "a", status: .improving),
            pattern(.lexis, key: "b", status: .mastered),
        ]
        let summary = ProgressSummary.make(profile: profile, streak: StreakState())
        #expect(summary.progress(for: .grammar)?.trend == .improving)
        #expect(summary.progress(for: .lexis)?.trend == .improving)
    }

    @Test
    func onlyActivePatternsReadAsSteadyNeverDowngrade() {
        var profile = LearnerProfile()
        profile.patterns = [pattern(.grammar, key: "a", status: .active)]
        let summary = ProgressSummary.make(profile: profile, streak: StreakState())
        // Active issues are real, but the surface never frames them as a downgrade.
        #expect(summary.progress(for: .grammar)?.trend == .steady)
    }

    @Test
    func lensWithLevelButNoPatternsIsSteady() {
        var profile = LearnerProfile()
        profile.levels = [.discourse: 30]
        let summary = ProgressSummary.make(profile: profile, streak: StreakState())
        #expect(summary.progress(for: .discourse)?.trend == .steady)
    }

    // MARK: - Streak passthrough

    @Test
    func streakCarriesThroughVerbatim() {
        let streak = StreakState(current: 4, best: 9, lastReviewDay: day0)
        let summary = ProgressSummary.make(profile: LearnerProfile(), streak: streak)
        #expect(summary.streak == streak)
    }

    // MARK: - Pronunciation GOP summary

    private func signals(_ phonemes: [(String, Double, Int)]) -> PronunciationSignals {
        PronunciationSignals(
            overallGOP: phonemes.isEmpty ? 0
                : phonemes.map { $0.1 * Double($0.2) }.reduce(0, +) / Double(phonemes.map(\.2).reduce(0, +)),
            perPhoneme: phonemes.map { .init(symbol: $0.0, meanGOP: $0.1, count: $0.2) },
            worstWords: []
        )
    }

    @Test
    func emptyCorpusReportsNoPronunciationData() {
        let summary = ProgressSummary.make(profile: LearnerProfile(), streak: StreakState())
        #expect(summary.pronunciation.hasData == false)
        #expect(summary.pronunciation.noteCount == 0)
        #expect(summary.pronunciation.weakestPhonemes.isEmpty)
    }

    @Test
    func pronunciationSummaryAggregatesCorpus() {
        let corpus = [
            signals([("th", -8.0, 2), ("s", -1.0, 3)]),
            signals([("th", -6.0, 1), ("r", -2.0, 2)]),
        ]
        let summary = ProgressSummary.make(
            profile: LearnerProfile(), streak: StreakState(), pronunciationCorpus: corpus
        )
        let pron = summary.pronunciation
        #expect(pron.hasData)
        #expect(pron.noteCount == 2)
        // /th/ is the worst (lowest baseline GOP) → first in weakest.
        #expect(pron.weakestPhonemes.first?.symbol == "th")
        #expect(pron.weakestPhonemes.count <= ProgressSummary.weakestPhonemeLimit)
        // Corpus mean GOP is ≤ 0.
        #expect(pron.meanGOP <= 0)
    }

    @Test
    func weakestPhonemesAreCappedAndOrderedWorstFirst() {
        let corpus = [
            signals([("a", -1.0, 1), ("b", -2.0, 1), ("c", -3.0, 1), ("d", -4.0, 1), ("e", -5.0, 1)]),
        ]
        let pron = ProgressSummary.make(
            profile: LearnerProfile(), streak: StreakState(), pronunciationCorpus: corpus
        ).pronunciation
        #expect(pron.weakestPhonemes.count == ProgressSummary.weakestPhonemeLimit)
        #expect(pron.weakestPhonemes.map(\.symbol) == ["e", "d", "c"])
    }

    @Test
    func masteredPhonemePatternsAreCounted() {
        var profile = LearnerProfile()
        profile.patterns = [
            pattern(.pronunciation, key: "pron-phoneme-th", status: .mastered),
            pattern(.pronunciation, key: "pron-phoneme-s", status: .active),
        ]
        let pron = ProgressSummary.make(profile: profile, streak: StreakState()).pronunciation
        #expect(pron.masteredPhonemes == 1)
    }

    @Test
    func deterministicSameInputsSameOutput() {
        var profile = LearnerProfile()
        profile.levels = [.grammar: 20]
        profile.patterns = [pattern(.grammar, key: "a", status: .mastered)]
        let corpus = [signals([("th", -7.0, 2), ("s", -1.0, 1)])]
        let a = ProgressSummary.make(profile: profile, streak: StreakState(current: 3, best: 5), pronunciationCorpus: corpus)
        let b = ProgressSummary.make(profile: profile, streak: StreakState(current: 3, best: 5), pronunciationCorpus: corpus)
        #expect(a == b)
    }
}
