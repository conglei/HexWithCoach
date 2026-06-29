import Foundation
import Testing
@testable import VocoCore

struct LearnerProfileTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func obs(
        _ lens: Lens = .grammar,
        key: String = "drop-articles",
        l1: String? = nil
    ) -> VerifiedObservation {
        VerifiedObservation(
            lens: lens, key: key,
            summary: "drops articles before abstract nouns",
            rule: "Use 'the' before specific abstract nouns.",
            severity: 3,
            example: ExampleRef(transcriptID: UUID(), span: "I value honesty"),
            inferredL1: l1
        )
    }

    @Test
    func newObservationCreatesActivePattern() {
        var profile = LearnerProfile()
        profile.integrate([obs()], at: t0)

        #expect(profile.patterns.count == 1)
        let p = profile.patterns[0]
        #expect(p.frequency == 1)
        #expect(p.status == .active)
        #expect(p.examples.count == 1)
        #expect(profile.updatedAt == t0)
    }

    @Test
    func repeatedOccurrenceRaisesFrequencyAndRecency() {
        var profile = LearnerProfile()
        profile.integrate([obs()], at: t0)
        let later = t0.addingTimeInterval(3600)
        profile.integrate([obs()], at: later)

        #expect(profile.patterns.count == 1) // merged, not duplicated
        #expect(profile.patterns[0].frequency == 2)
        #expect(profile.patterns[0].recency == later)
    }

    @Test
    func patternTransitionsToMasteredWhenItStopsRecurring() {
        var profile = LearnerProfile()
        profile.integrate([obs()], at: t0)
        #expect(profile.patterns[0].status == .active)

        // A week later with no recurrence → improving.
        profile.recomputeStatuses(asOf: t0.addingTimeInterval(8 * 24 * 3600))
        #expect(profile.patterns[0].status == .improving)

        // A month later → mastered (a "win").
        profile.recomputeStatuses(asOf: t0.addingTimeInterval(31 * 24 * 3600))
        #expect(profile.patterns[0].status == .mastered)
    }

    @Test
    func levelsAreGrowthFramedOnlyUp() {
        var profile = LearnerProfile()
        profile.integrate([obs()], at: t0)
        let baseline = profile.level(for: .grammar)

        // Master it → grammar level rises.
        profile.recomputeStatuses(asOf: t0.addingTimeInterval(31 * 24 * 3600))
        let masteredLevel = profile.level(for: .grammar)
        #expect(masteredLevel > baseline)

        // It recurs (regression): status goes back to active, but the level holds.
        profile.integrate([obs()], at: t0.addingTimeInterval(40 * 24 * 3600))
        #expect(profile.patterns[0].status == .active)
        #expect(profile.level(for: .grammar) == masteredLevel) // never drops
    }

    @Test
    func l1IsInferredOnceAndNotOverwritten() {
        var profile = LearnerProfile()
        profile.integrate([obs(l1: "Mandarin")], at: t0)
        #expect(profile.inferredL1 == "Mandarin")
        // A later observation guessing a different L1 doesn't clobber it.
        profile.integrate([obs(key: "other", l1: "Spanish")], at: t0.addingTimeInterval(3600))
        #expect(profile.inferredL1 == "Mandarin")
    }

    @Test
    func examplesAreCappedPerPattern() {
        var profile = LearnerProfile()
        let policy = ProfileUpdatePolicy(maxExamplesPerPattern: 3)
        for i in 0 ..< 6 {
            let o = VerifiedObservation(
                lens: .lexis, key: "overuse-very",
                summary: "overuses 'very'", rule: "Prefer a stronger adjective.",
                example: ExampleRef(transcriptID: UUID(), span: "very \(i)")
            )
            profile.integrate([o], at: t0.addingTimeInterval(Double(i)), policy: policy)
        }
        #expect(profile.patterns.count == 1)
        #expect(profile.patterns[0].frequency == 6)
        #expect(profile.patterns[0].examples.count == 3) // capped, keeps most recent
        #expect(profile.patterns[0].examples.last?.span == "very 5")
    }

    @Test
    func roundTripsThroughCodable() throws {
        var profile = LearnerProfile(inferredL1: "Mandarin", goals: ["sound natural in standups"])
        profile.integrate([obs(), obs(.prosody, key: "fillers")], at: t0)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(profile)
        let restored = try decoder.decode(LearnerProfile.self, from: data)
        #expect(restored == profile)
    }
}
