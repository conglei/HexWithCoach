import Foundation
import SwiftData
import Testing
import VocoCore
@testable import Voco

/// Behavior spec for the Practice persistence layer (PR-1).
///
/// Practice items are modeled as their *own* type, deliberately separate from
/// `TranscriptEntry`, so pasted / coach / phrasebook targets are never captures
/// and never surface in History. These tests pin that separation, the
/// `segments`/`attempts` round-trip, and the cascade-delete of attempts.
@MainActor
@Suite struct PracticeStoreTests {

    /// Retain the container for the test's lifetime: returning a bare
    /// `ModelContext` lets SwiftData deallocate the container out from under it
    /// and SIGTRAP. Both the context and its owning container are handed back.
    private func makeStore() -> (ModelContext, ModelContainer) {
        let container = try! ModelContainer(
            for: TranscriptStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (ModelContext(container), container)
    }

    // MARK: Round-trip + cascade

    @Test func persistsItemWithSegmentsAndAttempts() throws {
        let (ctx, container) = makeStore()
        _ = container   // keep alive

        let item = PracticeItem(
            title: "Past tense",
            sourceText: "Yesterday I went to the store. It was closed.",
            segments: ["Yesterday I went to the store.", "It was closed."],
            origin: .coachInsight,
            sourceID: UUID()
        )
        ctx.insert(item)
        item.attempts.append(PracticeAttempt(perSegmentScores: [0.8, 0.6], gopDelta: 0.1))
        item.attempts.append(PracticeAttempt(perSegmentScores: [0.95, 0.9], gopDelta: 0.25))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PracticeItem>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.segments == ["Yesterday I went to the store.", "It was closed."])
        #expect(stored.origin == .coachInsight)
        #expect(stored.sourceID != nil)
        #expect(stored.attempts.count == 2)
        // Per-segment scores and the GOP delta round-trip through SwiftData.
        let scores = stored.attempts.map(\.perSegmentScores).sorted { $0[0] < $1[0] }
        #expect(scores == [[0.8, 0.6], [0.95, 0.9]])
    }

    @Test func deletingItemCascadesToAttempts() throws {
        let (ctx, container) = makeStore()
        _ = container

        let item = PracticeItem(sourceText: "Practice", segments: ["Practice"])
        ctx.insert(item)
        item.attempts.append(PracticeAttempt(perSegmentScores: [0.5]))
        item.attempts.append(PracticeAttempt(perSegmentScores: [0.9]))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<PracticeAttempt>()).count == 2)

        ctx.delete(item)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<PracticeItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<PracticeAttempt>()).isEmpty)   // cascade removed them
    }

    // MARK: Separation from History

    @Test func practiceItemsNeverSurfaceInTranscriptQueries() throws {
        let (ctx, container) = makeStore()
        _ = container

        // A real capture and a practice item coexist in the same store…
        ctx.insert(TranscriptEntry(text: "a real captured note", date: Date(), kind: .note))
        ctx.insert(PracticeItem(sourceText: "pasted target", segments: ["pasted target"], origin: .pasted))
        try ctx.save()

        // …but a History-style fetch only ever returns transcripts.
        let history = try ctx.fetch(FetchDescriptor<TranscriptEntry>())
        #expect(history.count == 1)
        #expect(history.allSatisfy { $0.text == "a real captured note" })
        // And practice items live entirely in their own type.
        #expect(try ctx.fetch(FetchDescriptor<PracticeItem>()).count == 1)
    }

    // MARK: Origin accessor

    @Test func originAccessorRoundTripsAndDefaults() {
        let item = PracticeItem(sourceText: "x", segments: ["x"], origin: .phrasebook)
        #expect(item.origin == .phrasebook)
        #expect(item.originRaw == "phrasebook")

        item.origin = .coachInsight
        #expect(item.originRaw == "coachInsight")

        item.originRaw = "not-an-origin"
        #expect(item.origin == .pasted)   // safe default rather than a trap
    }

    // MARK: Paste flow (PR-3)

    /// The paste-to-practice ingest: segment arbitrary text, build a `.pasted`
    /// item from those segments, persist it, then attach an attempt with the
    /// per-segment scores — and confirm none of it leaks into History.
    @Test func pasteSessionCreatesPastedItemWithSegmentedText() throws {
        let (ctx, container) = makeStore()
        _ = container

        let raw = "  Hello there. How are you? I am fine!  "
        let segments = SentenceSegmenter.segments(from: raw)
        #expect(segments == ["Hello there.", "How are you?", "I am fine!"])

        let item = PracticeStore.pasted(raw.trimmingCharacters(in: .whitespacesAndNewlines), segments: segments)
        ctx.insert(item)
        try ctx.save()

        // Drill finishes → save one attempt with per-segment scores onto the item.
        item.attempts.append(PracticeAttempt(perSegmentScores: [0.9, 0.7, 0.95], gopDelta: 0.12, item: item))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PracticeItem>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.origin == .pasted)
        #expect(stored.sourceID == nil)
        #expect(stored.segments == ["Hello there.", "How are you?", "I am fine!"])
        #expect(stored.attempts.count == 1)
        #expect(stored.attempts.first?.perSegmentScores == [0.9, 0.7, 0.95])
        #expect(stored.attempts.first?.gopDelta == 0.12)

        // Pasted practice must never surface in History.
        #expect(try ctx.fetch(FetchDescriptor<TranscriptEntry>()).isEmpty)
    }

    @Test func storeHelpersSetOriginAndSource() {
        let sourceID = UUID()
        let pasted = PracticeStore.pasted("hi", segments: ["hi"])
        #expect(pasted.origin == .pasted)
        #expect(pasted.sourceID == nil)

        let coach = PracticeStore.coachInsight("hi", segments: ["hi"], sourceID: sourceID)
        #expect(coach.origin == .coachInsight)
        #expect(coach.sourceID == sourceID)

        let phrase = PracticeStore.phrasebook("hi", segments: ["hi"], sourceID: sourceID)
        #expect(phrase.origin == .phrasebook)
        #expect(phrase.sourceID == sourceID)
    }
}
