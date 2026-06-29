import Foundation
import SwiftData
import Testing
import VocoCore
@testable import Voco

/// CF-3 — the app-side persistence half of the progress loop: the additive
/// `PracticeItem.patternKey` + `lensRaw` tags round-trip through SwiftData, default
/// safely (so the schema stays at six types — the GUARD invariant), and the
/// `PracticeStore` helper threads them through. The pure aggregation (reps, deltas,
/// frequency-drop verdict) is covered in VocoCore's `PracticeProgressTests`.
@MainActor
@Suite struct PracticeItemTaggingTests {

    /// Retain the container for the test's lifetime (SIGTRAP guard).
    private func makeStore() -> (ModelContext, ModelContainer) {
        let container = try! ModelContainer(
            for: TranscriptStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (ModelContext(container), container)
    }

    // MARK: Tags round-trip + default

    @Test func patternKeyAndLensRoundTripThroughSwiftData() throws {
        let (ctx, container) = makeStore()
        _ = container

        let item = PracticeItem(
            sourceText: "I overuse basically in meetings",
            segments: ["I overuse basically in meetings"],
            origin: .coachInsight,
            kind: .wordSwap,
            sourceID: UUID(),
            patternKey: "overuse-basically",
            lens: .lexis
        )
        ctx.insert(item)
        item.attempts.append(PracticeAttempt(perSegmentScores: [0.82]))
        try ctx.save()

        let stored = try #require(try ctx.fetch(FetchDescriptor<PracticeItem>()).first)
        #expect(stored.patternKey == "overuse-basically")
        #expect(stored.lens == .lexis)
        #expect(stored.lensRaw == "lexis")
    }

    @Test func tagsDefaultToNilSoExistingItemsAreUnchanged() {
        // Every pre-CF-3 item — and any item built without tags — carries no focus
        // attribution, so the migration is behavior-preserving and additive.
        let item = PracticeItem(sourceText: "x", segments: ["x"])
        #expect(item.patternKey == nil)
        #expect(item.lens == nil)
        #expect(item.lensRaw == nil)
    }

    @Test func lensAccessorFallsBackToNilRatherThanTrapping() {
        let item = PracticeItem(sourceText: "x", segments: ["x"], lens: .prosody)
        item.lensRaw = "not-a-lens"
        #expect(item.lens == nil)   // unknown raw → nil, never a crash
    }

    // MARK: Store helper threads the tags

    @Test func coachInsightTagsPatternAndLens() {
        let id = UUID()
        let item = PracticeStore.coachInsight(
            "better word", segments: ["better word"], sourceID: id,
            kind: .wordSwap, patternKey: "overuse-basically", lens: .lexis, title: "x")
        #expect(item.patternKey == "overuse-basically")
        #expect(item.lens == .lexis)
        #expect(item.origin == .coachInsight)
    }

    @Test func coachInsightTagsDefaultNilForExistingCallers() {
        // The CF-2 callers that pass only `kind` must keep compiling and stay untagged.
        let item = PracticeStore.coachInsight("hi", segments: ["hi"], sourceID: UUID(), kind: .wordSwap)
        #expect(item.patternKey == nil)
        #expect(item.lens == nil)
    }

    // MARK: A tagged attempt is attributable for the practice→drop loop

    @Test func taggedAttemptsMapToAttributablePracticeFacts() throws {
        let (ctx, container) = makeStore()
        _ = container

        let item = PracticeStore.coachInsight(
            "I overuse basically in meetings",
            segments: ["I overuse basically in meetings"],
            sourceID: UUID(), kind: .wordSwap,
            patternKey: "overuse-basically", lens: .lexis, title: "x")
        ctx.insert(item)
        ctx.insert(PracticeAttempt(perSegmentScores: [0.6, 0.8], gopDelta: nil, item: item))
        try ctx.save()

        // Mirror CoachFocusModel.loadPracticeFacts: an attempt + its parent's tags
        // become a pure PracticeAttemptFact attributable to (lens, patternKey).
        let attempts = try ctx.fetch(FetchDescriptor<PracticeAttempt>())
        let facts: [PracticeAttemptFact] = attempts.compactMap { a in
            guard let parent = a.item else { return nil }
            let s = a.perSegmentScores
            return PracticeAttemptFact(
                date: a.date, kind: parent.kind, lens: parent.lens,
                patternKey: parent.patternKey,
                score: s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count),
                gopDelta: a.gopDelta)
        }
        #expect(facts.count == 1)
        let fact = try #require(facts.first)
        #expect(fact.lens == .lexis)
        #expect(fact.patternKey == "overuse-basically")
        #expect(abs(fact.score - 0.7) < 0.0001)   // mean of [0.6, 0.8]

        // And those facts feed the pure accumulation summary.
        let summary = PracticeLog.summary(facts: facts, now: Date())
        #expect(summary.byLens.first?.lens == .lexis)
    }
}
