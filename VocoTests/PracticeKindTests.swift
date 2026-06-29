import Foundation
import SwiftData
import Testing
import VocoCore
@testable import Voco

/// CF-2 — the app-side persistence half of the typed practice framework: the
/// `PracticeItem.kind` attribute round-trips through SwiftData, defaults safely,
/// and the `PracticeStore` helpers tag items with the right kind. The pure
/// drill-selection + judge logic is covered in VocoCore's `PracticeDrillTests`.
@MainActor
@Suite struct PracticeKindTests {

    /// Retain the container for the test's lifetime (SIGTRAP guard), mirroring
    /// `PracticeStoreTests`.
    private func makeStore() -> (ModelContext, ModelContainer) {
        let container = try! ModelContainer(
            for: TranscriptStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (ModelContext(container), container)
    }

    // MARK: kind round-trip + default

    @Test func kindRoundTripsThroughSwiftData() throws {
        let (ctx, container) = makeStore()
        _ = container

        let item = PracticeItem(
            sourceText: "I overuse basically in meetings",
            segments: ["I overuse basically in meetings"],
            origin: .coachInsight,
            kind: .wordSwap,
            sourceID: UUID()
        )
        ctx.insert(item)
        item.attempts.append(PracticeAttempt(perSegmentScores: [0.82]))
        try ctx.save()

        let stored = try #require(try ctx.fetch(FetchDescriptor<PracticeItem>()).first)
        #expect(stored.kind == .wordSwap)
        #expect(stored.kindRaw == "wordSwap")
        #expect(stored.attempts.count == 1)
    }

    @Test func kindDefaultsToShadow() {
        // Every existing (PR-1/PR-3) item — and any item built without a kind — is
        // a shadow drill, so the schema migration is behavior-preserving.
        let item = PracticeItem(sourceText: "x", segments: ["x"])
        #expect(item.kind == .shadow)
        #expect(item.kindRaw == "shadow")
    }

    @Test func kindAccessorFallsBackRatherThanTrapping() {
        let item = PracticeItem(sourceText: "x", segments: ["x"], kind: .wordSwap)
        item.kindRaw = "not-a-kind"
        #expect(item.kind == .shadow)   // safe default, never a crash
    }

    // MARK: Store helpers tag the kind

    @Test func pastedIsAlwaysShadow() {
        #expect(PracticeStore.pasted("hi", segments: ["hi"]).kind == .shadow)
    }

    @Test func coachInsightDefaultsShadowAndAcceptsWordSwap() {
        let id = UUID()
        let shadow = PracticeStore.coachInsight("hi", segments: ["hi"], sourceID: id)
        #expect(shadow.kind == .shadow)

        let swap = PracticeStore.coachInsight("better word", segments: ["better word"], sourceID: id, kind: .wordSwap)
        #expect(swap.kind == .wordSwap)
        #expect(swap.origin == .coachInsight)
        #expect(swap.sourceID == id)
    }

    // MARK: A word-swap attempt persists tagged with its kind (feeds CF-3)

    @Test func wordSwapAttemptPersistsWithKind() throws {
        let (ctx, container) = makeStore()
        _ = container

        // Simulate what PracticeView.persistAttempt does for a lexis card drill.
        let item = PracticeStore.coachInsight(
            "I overuse basically in meetings",
            segments: ["I overuse basically in meetings"],
            sourceID: UUID(), kind: .wordSwap, title: "A crisper word")
        ctx.insert(item)
        ctx.insert(PracticeAttempt(perSegmentScores: [0.82], gopDelta: nil, item: item))
        try ctx.save()

        // A query that wanted "only word-swap attempts" (CF-3) can filter by kind.
        let swapItems = try ctx.fetch(FetchDescriptor<PracticeItem>())
            .filter { $0.kind == .wordSwap }
        #expect(swapItems.count == 1)
        #expect(swapItems.first?.attempts.first?.perSegmentScores == [0.82])
        // And it never leaks into History.
        #expect(try ctx.fetch(FetchDescriptor<TranscriptEntry>()).isEmpty)
    }
}
