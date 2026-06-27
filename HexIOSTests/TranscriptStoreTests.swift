import Foundation
import SwiftData
import Testing
import HexCore
@testable import HexIOS

/// Behavior spec for the iOS persistence layer: the `ensureUniqueIDs` dedup
/// migration and the `CoachCardEntity` ⇄ `CoachCard` mapping.
///
/// Written against intended behavior, not the implementation:
///   • `ensureUniqueIDs` exists because a SwiftData lightweight migration once
///     stamped every pre-existing row with the *same* default UUID, which then
///     collided in `ForEach` and broke card↔transcript links. After it runs,
///     every transcript must have a distinct id, with payloads untouched, and
///     re-running must be a stable no-op.
///   • `CoachCardEntity(card:)` is a faithful mirror of the pure `CoachCard`, and
///     the entity's enum accessors must degrade gracefully on unknown raw values
///     rather than trap.
@MainActor
@Suite struct TranscriptStoreTests {

    private func makeContext() -> ModelContext {
        let container = try! ModelContainer(
            for: TranscriptEntry.self, CoachCardEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func ids(in context: ModelContext) -> [UUID] {
        (try? context.fetch(FetchDescriptor<TranscriptEntry>()))?.map(\.id) ?? []
    }

    // MARK: ensureUniqueIDs

    @Test func deduplicatesCollidingIDs() {
        let ctx = makeContext()
        let shared = UUID()
        for i in 0..<3 {
            let e = TranscriptEntry(text: "row \(i)", date: Date(), kind: .note)
            e.id = shared            // simulate the migration's identical-default-UUID bug
            ctx.insert(e)
        }
        try? ctx.save()

        TranscriptStore.ensureUniqueIDs(in: ctx)

        let result = ids(in: ctx)
        #expect(result.count == 3)
        #expect(Set(result).count == 3)                       // all now distinct
        #expect(result.filter { $0 == shared }.count == 1)    // exactly one keeps the original
    }

    @Test func preservesAlreadyUniqueIDs() {
        let ctx = makeContext()
        for i in 0..<3 {
            ctx.insert(TranscriptEntry(text: "row \(i)", date: Date(), kind: .note))
        }
        try? ctx.save()
        let before = Set(ids(in: ctx))

        TranscriptStore.ensureUniqueIDs(in: ctx)

        #expect(Set(ids(in: ctx)) == before)   // untouched when already unique
    }

    @Test func preservesPayloadWhileDeduping() {
        let ctx = makeContext()
        let shared = UUID()
        let date = Date(timeIntervalSinceReferenceDate: 5000)
        for i in 0..<2 {
            let e = TranscriptEntry(text: "kept \(i)", date: date, kind: .dictation)
            e.id = shared
            ctx.insert(e)
        }
        try? ctx.save()

        TranscriptStore.ensureUniqueIDs(in: ctx)

        let all = (try? ctx.fetch(FetchDescriptor<TranscriptEntry>())) ?? []
        #expect(all.allSatisfy { $0.text.hasPrefix("kept ") })
        #expect(all.allSatisfy { $0.date == date })
        #expect(all.allSatisfy { $0.kind == .dictation })
    }

    @Test func idempotentAcrossRuns() {
        let ctx = makeContext()
        let shared = UUID()
        for _ in 0..<4 {
            let e = TranscriptEntry(text: "x", date: Date(), kind: .note)
            e.id = shared
            ctx.insert(e)
        }
        try? ctx.save()

        TranscriptStore.ensureUniqueIDs(in: ctx)
        let afterFirst = Set(ids(in: ctx))
        TranscriptStore.ensureUniqueIDs(in: ctx)
        let afterSecond = Set(ids(in: ctx))

        #expect(afterFirst.count == 4)
        #expect(afterSecond == afterFirst)   // second run changes nothing
    }

    @Test func emptyStoreIsHandled() {
        let ctx = makeContext()
        TranscriptStore.ensureUniqueIDs(in: ctx)   // must not crash
        #expect(ids(in: ctx).isEmpty)
    }

    // MARK: CoachCardEntity mapping

    @Test func entityMirrorsAllCardFields() {
        let tID = UUID()
        let created = Date(timeIntervalSinceReferenceDate: 9000)
        let card = CoachCard(
            id: UUID(),
            kind: .improvement,
            lens: .grammar,
            key: "subject-verb",
            title: "Try: she goes",
            detail: "‘she go’ → ‘she goes’",
            originalSpan: "she go",
            nativeRewrite: "she goes",
            transcriptID: tID,
            recurrenceNote: "3rd time this week",
            createdAt: created
        )

        let e = CoachCardEntity(card: card)

        #expect(e.id == card.id)
        #expect(e.key == "subject-verb")
        #expect(e.title == "Try: she goes")
        #expect(e.detail == "‘she go’ → ‘she goes’")
        #expect(e.originalSpan == "she go")
        #expect(e.nativeRewrite == "she goes")
        #expect(e.transcriptID == tID)
        #expect(e.recurrenceNote == "3rd time this week")
        #expect(e.createdAt == created)
        #expect(e.kind == .improvement)
        #expect(e.lens == .grammar)
        #expect(e.status == .new)   // freshly-created cards start unseen
    }

    @Test func statusSetterRoundTrips() {
        let e = CoachCardEntity(card: CoachCard(
            kind: .win, lens: .lexis, key: "k", title: "t", detail: "d", createdAt: Date()
        ))
        e.status = .done
        #expect(e.statusRaw == "done")
        #expect(e.status == .done)
    }

    @Test func enumAccessorsFallBackOnUnknownRaw() {
        let e = CoachCardEntity(card: CoachCard(
            kind: .improvement, lens: .grammar, key: "k", title: "t", detail: "d", createdAt: Date()
        ))
        e.kindRaw = "not-a-kind"
        e.lensRaw = "not-a-lens"
        e.statusRaw = "not-a-status"
        #expect(e.kind == .improvement)   // safe defaults rather than a trap
        #expect(e.lens == .grammar)
        #expect(e.status == .new)
    }

    @Test func transcriptEntryKindFallsBackToNote() {
        let e = TranscriptEntry(text: "t", date: Date(), kind: .dictation)
        e.kindRaw = "garbage"
        #expect(e.kind == .note)
    }
}
