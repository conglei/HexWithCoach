import Foundation
import Testing
@testable import VocoCore

/// TDD for RC-2: curating verified insights (CE-3) into a small, deduped,
/// positive-leaning set of teachable cards, plus BYOK cost estimation.
struct CoachCardTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let tid = UUID()

    private func insight(_ key: String = "missing-article", lens: Lens = .grammar, severity: Int = 3) -> CoachInsight {
        CoachInsight(
            transcriptID: tid, lens: lens, key: key,
            summary: "drops articles", rule: "Use 'the' before specific nouns.",
            originalSpan: "went to store", nativeRewrite: "went to the store", severity: severity
        )
    }

    private func profile(frequency: Int, key: String = "missing-article") -> LearnerProfile {
        var p = LearnerProfile()
        for i in 0 ..< frequency {
            p.integrate([VerifiedObservation(
                lens: .grammar, key: key, summary: "drops articles", rule: "r",
                example: ExampleRef(transcriptID: UUID(), span: "span \(i)")
            )], at: t0.addingTimeInterval(Double(i)))
        }
        return p
    }

    // MARK: Improvement cards

    @Test
    func insightBecomesImprovementCard() {
        let analysis = CoachAnalysis(insights: [insight()], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [], profile: LearnerProfile(), now: t0)
        #expect(cards.count == 1)
        let c = cards[0]
        #expect(c.kind == .improvement)
        #expect(c.lens == .grammar)
        #expect(c.originalSpan == "went to store")
        #expect(c.nativeRewrite == "went to the store")
        #expect(c.transcriptID == tid)
    }

    @Test
    func improvementCardCopiesContextAndPracticeText() {
        let withFields = CoachInsight(
            transcriptID: tid, lens: .grammar, key: "missing-article",
            summary: "drops articles", rule: "Use 'the' before specific nouns.",
            originalSpan: "went to store", nativeRewrite: "went to the store", severity: 3,
            context: "I went to store yesterday.", practiceText: "I went to the store yesterday."
        )
        let analysis = CoachAnalysis(insights: [withFields], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [], profile: LearnerProfile(), now: t0)
        #expect(cards[0].context == "I went to store yesterday.")
        #expect(cards[0].practiceText == "I went to the store yesterday.")
    }

    @Test
    func improvementCardLeavesEmptyContextAndPracticeTextAsNil() {
        // The default `insight()` helper has empty context/practiceText → nil on the card.
        let analysis = CoachAnalysis(insights: [insight()], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [], profile: LearnerProfile(), now: t0)
        #expect(cards[0].context == nil)
        #expect(cards[0].practiceText == nil)
    }

    @Test
    func recurringInsightGetsFrequencyNote() {
        let analysis = CoachAnalysis(insights: [insight()], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [], profile: profile(frequency: 4), now: t0)
        #expect(cards[0].recurrenceNote?.contains("4") == true)
    }

    @Test
    func newInsightHasNoFrequencyNote() {
        let analysis = CoachAnalysis(insights: [insight()], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [], profile: profile(frequency: 1), now: t0)
        #expect(cards[0].recurrenceNote == nil)
    }

    @Test
    func dedupesInsightsByKey() {
        let analysis = CoachAnalysis(insights: [insight(), insight()], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [], profile: LearnerProfile(), now: t0)
        #expect(cards.filter { $0.kind == .improvement }.count == 1)
    }

    // MARK: Wins + ordering

    @Test
    func masteredPatternBecomesWinCard() {
        let pattern = RecurringPattern(
            lens: .lexis, key: "overuse-very", summary: "overused 'very'", rule: "r",
            frequency: 6, firstSeen: t0, recency: t0, status: .mastered
        )
        let analysis = CoachAnalysis(insights: [insight()], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [pattern], profile: LearnerProfile(), now: t0)
        #expect(cards.contains { $0.kind == .win && $0.lens == .lexis })
    }

    @Test
    func positiveLeaningPutsAWinFirst() {
        let pattern = RecurringPattern(
            lens: .lexis, key: "overuse-very", summary: "overused 'very'", rule: "r",
            frequency: 6, firstSeen: t0, recency: t0, status: .mastered
        )
        let analysis = CoachAnalysis(insights: [insight()], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [pattern], profile: LearnerProfile(), now: t0)
        #expect(cards.first?.kind == .win)
    }

    @Test
    func capsAtLimit() {
        let insights = (0 ..< 10).map { insight("key-\($0)") }
        let analysis = CoachAnalysis(insights: insights, focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [], profile: LearnerProfile(), now: t0, limit: 3)
        #expect(cards.count == 3)
    }

    @Test
    func ordersImprovementsBySeverity() {
        let low = insight("low", severity: 1)
        let high = insight("high", severity: 5)
        let analysis = CoachAnalysis(insights: [low, high], focuses: [], signals: .init())
        let cards = CoachCardCurator.curate(analysis: analysis, wins: [], profile: LearnerProfile(), now: t0)
        #expect(cards.first?.key == "high")
    }

    // MARK: Cost estimation

    @Test
    func costScalesWithOutputTokens() {
        let a = CoachCostEstimator.usd(promptTokens: 1000, outputTokens: 500, model: GeminiClient.Model.flash)
        let b = CoachCostEstimator.usd(promptTokens: 1000, outputTokens: 1000, model: GeminiClient.Model.flash)
        #expect(b > a)
    }

    @Test
    func strongerModelCostsMore() {
        let lite = CoachCostEstimator.usd(promptTokens: 1000, outputTokens: 1000, model: GeminiClient.Model.flashLite)
        let flash = CoachCostEstimator.usd(promptTokens: 1000, outputTokens: 1000, model: GeminiClient.Model.flash)
        #expect(flash > lite)
        #expect(lite > 0)
    }
}
