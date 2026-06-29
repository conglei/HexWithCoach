import Foundation
import SwiftData
import Testing
import VocoCore
@testable import Voco

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
            for: TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
            CoachObservation.self, PracticeItem.self, PracticeAttempt.self,
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
            context: "Every morning she go to the gym.",
            practiceText: "Every morning she goes to the gym.",
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
        #expect(e.context == "Every morning she go to the gym.")
        #expect(e.practiceText == "Every morning she goes to the gym.")
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

    // MARK: Feed data path (FX-1)

    /// Build a container, hold it for the call's lifetime (SwiftData SIGTRAP
    /// guard), and return both so the model graph stays alive while we query.
    private func makeContainerAndContext() -> (ModelContainer, ModelContext) {
        let container = try! ModelContainer(
            for: TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
            CoachObservation.self, PracticeItem.self, PracticeAttempt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    /// FX-1 regression: the Coach tab's Feedback feed was empty even though
    /// `.new` `CoachCardEntity` rows existed (the embedded `ReviewView`'s `@Query`
    /// was never bound to a `modelContext`). The pure gating was always correct;
    /// what regressed was the *data path*. This pins the contract the feed relies
    /// on: a `.new` card in the store, filtered exactly as `ReviewView.cards`
    /// does, must drive `ReviewFeedGating.feedState` to `.feed` — independent of
    /// key presence (keyless objective lane authors these cards).
    @Test func newCardInStoreDrivesFeedState() throws {
        let (container, ctx) = makeContainerAndContext()
        _ = container  // retain for the test's lifetime

        // A note exists, and the objective lane wrote one fresh card.
        ctx.insert(TranscriptEntry(text: "every morning she go", date: Date(), kind: .note))
        ctx.insert(CoachCardEntity(card: CoachCard(
            kind: .improvement, lens: .pronunciation, key: "th-think",
            title: "THINK", detail: "voiceless th", createdAt: Date()
        )))
        try ctx.save()

        let allCards = try ctx.fetch(FetchDescriptor<CoachCardEntity>())
        let newCards = allCards.filter { $0.status == .new }   // mirrors ReviewView.cards
        let notes = try ctx.fetch(FetchDescriptor<TranscriptEntry>())

        #expect(allCards.first?.status == .new)   // objective-lane cards start unseen
        #expect(newCards.count == 1)

        // Keyless: the card still wins → feed (not caughtUp/onboarding/key wall).
        let keyless = ReviewFeedGating.Inputs(
            hasCards: !newCards.isEmpty, hasKey: false, hasNotes: !notes.isEmpty
        )
        #expect(ReviewFeedGating.feedState(keyless) == .feed)
        let keyed = ReviewFeedGating.Inputs(
            hasCards: !newCards.isEmpty, hasKey: true, hasNotes: !notes.isEmpty
        )
        #expect(ReviewFeedGating.feedState(keyed) == .feed)
    }

    /// The companion: once every card is reviewed (no `.new` left) but notes
    /// remain, the feed correctly falls to "caught up" rather than showing stale
    /// cards — confirming the fix doesn't force the feed state on.
    @Test func reviewedCardsLeaveCaughtUpNotFeed() throws {
        let (container, ctx) = makeContainerAndContext()
        _ = container

        ctx.insert(TranscriptEntry(text: "a note", date: Date(), kind: .note))
        let card = CoachCardEntity(card: CoachCard(
            kind: .improvement, lens: .grammar, key: "k", title: "t", detail: "d", createdAt: Date()
        ))
        card.status = .done   // user already reviewed it
        ctx.insert(card)
        try ctx.save()

        let newCards = try ctx.fetch(FetchDescriptor<CoachCardEntity>()).filter { $0.status == .new }
        let notes = try ctx.fetch(FetchDescriptor<TranscriptEntry>())
        #expect(newCards.isEmpty)

        let inputs = ReviewFeedGating.Inputs(
            hasCards: !newCards.isEmpty, hasKey: false, hasNotes: !notes.isEmpty
        )
        #expect(ReviewFeedGating.feedState(inputs) == .caughtUp)
    }

    // MARK: Pronunciation result persistence (CI-3)

    private func sampleResult() -> PronunciationResult {
        PronunciationResult(words: [
            WordScore(word: "think", phonemes: [
                PhonemeScore(symbol: "θ", start: 0, end: 0.02, gop: -2.0),
                PhonemeScore(symbol: "ɪ", start: 0.02, end: 0.04, gop: -0.1),
            ]),
        ])
    }

    @Test func pronunciationResultCreatesSidecarAndRoundTrips() {
        let ctx = makeContext()
        let e = TranscriptEntry(text: "think", date: Date(), kind: .note)
        ctx.insert(e)
        #expect(e.pronunciationResult == nil)   // none captured yet
        #expect(e.analysis == nil)              // no sidecar until written (DM-1)

        e.pronunciationResult = sampleResult()
        #expect(e.analysis != nil)              // heavy blob now lives in the sidecar
        #expect(e.analysis?.pronunciationJSON != nil)
        #expect(e.pronunciationResult == sampleResult())
    }

    @Test func emptyPronunciationResultClearsTheSidecarField() {
        let e = TranscriptEntry(text: "x", date: Date(), kind: .note)
        e.pronunciationResult = sampleResult()
        e.pronunciationResult = PronunciationResult(words: [])
        #expect(e.analysis?.pronunciationJSON == nil)
        #expect(e.pronunciationResult == nil)
        #expect(e.pronunciationSignals == nil)   // on-row summary cleared too
    }

    @Test func pronunciationResultPopulatesOnRowSummary() {
        let e = TranscriptEntry(text: "think", date: Date(), kind: .note)
        #expect(e.pronunciationSignals == nil)
        #expect(e.pronunciationSummaryJSON == nil)

        e.pronunciationResult = sampleResult()
        #expect(e.pronunciationSummaryJSON != nil)   // compact summary on the row
        let signals = e.pronunciationSignals
        #expect(signals != nil)
        #expect(signals?.worstWords.first?.worstPhoneme == "θ")
    }

    // MARK: Word timings sidecar (DM-1)

    @Test func wordTimingsRoundTripThroughSidecar() {
        let ctx = makeContext()
        let e = TranscriptEntry(text: "hello world", date: Date(), kind: .note)
        ctx.insert(e)
        #expect(e.wordTimings == nil)
        #expect(e.analysis == nil)

        let timings = [
            WordTiming(word: "hello", start: 0.0, end: 0.4),
            WordTiming(word: "world", start: 0.4, end: 0.9),
        ]
        e.wordTimings = timings
        #expect(e.analysis != nil)               // create-on-write sidecar
        #expect(e.wordTimings == timings)
    }

    // MARK: Cascade delete (DM-1)

    @Test func deletingEntryCascadesToSidecar() throws {
        let ctx = makeContext()
        let e = TranscriptEntry(text: "think", date: Date(), kind: .note)
        ctx.insert(e)
        e.pronunciationResult = sampleResult()
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<TranscriptAnalysis>()).count == 1)

        ctx.delete(e)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<TranscriptEntry>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<TranscriptAnalysis>()).isEmpty)   // cascade removed it
    }
}
