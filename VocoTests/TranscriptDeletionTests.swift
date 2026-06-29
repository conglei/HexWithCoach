import Foundation
import SwiftData
import Testing
import VocoCore
@testable import Voco

/// Behavior spec for HS-3 cascade delete: removing a `TranscriptEntry` must clean
/// up every satellite it spawned — its `TranscriptAnalysis` sidecar (via the
/// `.cascade` rule), its audio file, its Review cards (`transcriptID`), its
/// observation-log rows (`noteID`), and its growth snapshot — leaving no orphans.
///
/// Also covers the DM-2 re-analyze dedup: clearing a note's observations before
/// re-recording them so frequency-over-time queries don't double-count.
@MainActor
@Suite struct TranscriptDeletionTests {

    /// Retains the `ModelContainer` for the test's lifetime. Holding only the
    /// `ModelContext` while the container deallocates dangles the store and traps
    /// SwiftData (SIGTRAP) on the next save.
    @MainActor
    private final class Env {
        let container: ModelContainer
        let context: ModelContext

        init() {
            container = try! ModelContainer(
                for: TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
                CoachObservation.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = container.mainContext
        }
    }

    private func cards(in ctx: ModelContext) -> [CoachCardEntity] {
        (try? ctx.fetch(FetchDescriptor<CoachCardEntity>())) ?? []
    }
    private func observations(in ctx: ModelContext) -> [CoachObservation] {
        (try? ctx.fetch(FetchDescriptor<CoachObservation>())) ?? []
    }
    private func entries(in ctx: ModelContext) -> [TranscriptEntry] {
        (try? ctx.fetch(FetchDescriptor<TranscriptEntry>())) ?? []
    }
    private func analyses(in ctx: ModelContext) -> [TranscriptAnalysis] {
        (try? ctx.fetch(FetchDescriptor<TranscriptAnalysis>())) ?? []
    }

    private func sampleResult() -> PronunciationResult {
        PronunciationResult(words: [
            WordScore(word: "think", phonemes: [
                PhonemeScore(symbol: "θ", start: 0, end: 0.02, gop: -2.0),
            ]),
        ])
    }

    /// Build a fully-populated note: a sidecar (via pronunciationResult), a card,
    /// two observations, and — when `AudioStore` can persist (the App Group container
    /// is reachable) — a real audio file on disk. Returns the persisted audio URL, or
    /// nil when the test environment has no App Group container so the audio-removal
    /// assertion is skipped rather than asserting on a path the store never owned.
    private func makeFullEntry(in ctx: ModelContext) -> (entry: TranscriptEntry, audioURL: URL?) {
        // A real temp audio file persisted through AudioStore so deletion has a file
        // to remove at the same portable filename the entry stores.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("del-test-\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: tmp.path, contents: Data([0x00, 0x01, 0x02]))
        let filename = AudioStore.persist(tmp)   // nil when no App Group container

        let entry = TranscriptEntry(
            text: "I think so", date: Date(), kind: .note, audioFilename: filename
        )
        ctx.insert(entry)
        entry.pronunciationResult = sampleResult()   // creates the cascade sidecar

        let card = CoachCardEntity(card: CoachCard(
            kind: .improvement, lens: .grammar, key: "k", title: "t", detail: "d",
            transcriptID: entry.id, createdAt: Date()
        ))
        ctx.insert(card)

        let obs1 = CoachObservation(noteID: entry.id, lensRaw: Lens.grammar.rawValue, originRaw: "llm", patternKey: "p")
        let obs2 = CoachObservation(noteID: entry.id, lensRaw: Lens.pronunciation.rawValue, originRaw: "objective", word: "think", gop: -2.0)
        ctx.insert(obs1)
        ctx.insert(obs2)
        try? ctx.save()

        return (entry, AudioStore.url(for: filename))
    }

    // MARK: - Cascade

    @Test func deleteCascadesToEverySatellite() throws {
        let env = Env()
        let ctx = env.context
        let (entry, audioURL) = makeFullEntry(in: ctx)
        let id = entry.id

        // Preconditions: all satellites present.
        #expect(entries(in: ctx).count == 1)
        #expect(analyses(in: ctx).count == 1)
        #expect(cards(in: ctx).count == 1)
        #expect(observations(in: ctx).count == 2)
        // Audio assertion only when the store actually retained a file (needs the
        // App Group container; absent in some CI sims). When present, it must exist
        // before delete and be gone after.
        if let audioURL { #expect(FileManager.default.fileExists(atPath: audioURL.path)) }

        TranscriptDeletion.delete(entry, in: ctx)

        // Everything for this id is gone.
        #expect(entries(in: ctx).isEmpty)
        #expect(analyses(in: ctx).isEmpty)                       // sidecar via .cascade
        #expect(cards(in: ctx).filter { $0.transcriptID == id }.isEmpty)
        #expect(observations(in: ctx).filter { $0.noteID == id }.isEmpty)
        if let audioURL { #expect(!FileManager.default.fileExists(atPath: audioURL.path)) }   // audio removed
    }

    @Test func deleteLeavesOtherNotesSatellitesIntact() throws {
        let env = Env()
        let ctx = env.context
        let (target, _) = makeFullEntry(in: ctx)

        // A second note with its own card + observation that must survive.
        let other = TranscriptEntry(text: "keep me", date: Date(), kind: .note)
        ctx.insert(other)
        ctx.insert(CoachCardEntity(card: CoachCard(
            kind: .improvement, lens: .grammar, key: "k2", title: "t2", detail: "d2",
            transcriptID: other.id, createdAt: Date()
        )))
        ctx.insert(CoachObservation(noteID: other.id, lensRaw: Lens.lexis.rawValue, originRaw: "llm"))
        try? ctx.save()

        TranscriptDeletion.delete(target, in: ctx)

        #expect(entries(in: ctx).map(\.id) == [other.id])
        #expect(cards(in: ctx).allSatisfy { $0.transcriptID == other.id })
        #expect(observations(in: ctx).allSatisfy { $0.noteID == other.id })
        #expect(cards(in: ctx).count == 1)
        #expect(observations(in: ctx).count == 1)
    }

    @Test func bulkDeleteRemovesAllSelectedAndTheirSatellites() throws {
        let env = Env()
        let ctx = env.context
        let (a, _) = makeFullEntry(in: ctx)
        let (b, _) = makeFullEntry(in: ctx)
        let survivor = TranscriptEntry(text: "survivor", date: Date(), kind: .note)
        ctx.insert(survivor)
        ctx.insert(CoachObservation(noteID: survivor.id, lensRaw: Lens.grammar.rawValue, originRaw: "llm"))
        try? ctx.save()

        TranscriptDeletion.delete([a, b], in: ctx)

        #expect(entries(in: ctx).map(\.id) == [survivor.id])
        #expect(cards(in: ctx).isEmpty)                          // both deleted notes' cards gone
        #expect(observations(in: ctx).count == 1)                // only survivor's remains
        #expect(observations(in: ctx).first?.noteID == survivor.id)
    }

    @Test func deleteMissingAudioIsSafe() throws {
        let env = Env()
        let ctx = env.context
        // No audio file, no satellites — delete must still remove the row cleanly.
        let entry = TranscriptEntry(text: "bare", date: Date(), kind: .note)
        ctx.insert(entry)
        try? ctx.save()

        TranscriptDeletion.delete(entry, in: ctx)
        #expect(entries(in: ctx).isEmpty)
    }

    // MARK: - Re-analyze observation dedup (DM-2)

    @Test func deleteObservationsClearsThenRecordPathDoesNotDuplicate() throws {
        let env = Env()
        let ctx = env.context
        let entry = TranscriptEntry(text: "go to store", date: Date(), kind: .note)
        ctx.insert(entry)

        // Simulate a first analysis recording observations for this note.
        let first = [
            CoachObservation(noteID: entry.id, lensRaw: Lens.grammar.rawValue, originRaw: "llm", patternKey: "drop-articles"),
            CoachObservation(noteID: entry.id, lensRaw: Lens.lexis.rawValue, originRaw: "llm", patternKey: "overuse-very"),
        ]
        for o in first { ctx.insert(o) }
        try? ctx.save()
        #expect(observations(in: ctx).filter { $0.noteID == entry.id }.count == 2)

        // Re-analyze path: clear this note's observations BEFORE re-recording.
        TranscriptDeletion.deleteObservations(noteID: entry.id, in: ctx)
        let reRecorded = [
            CoachObservation(noteID: entry.id, lensRaw: Lens.grammar.rawValue, originRaw: "llm", patternKey: "drop-articles"),
            CoachObservation(noteID: entry.id, lensRaw: Lens.lexis.rawValue, originRaw: "llm", patternKey: "overuse-very"),
        ]
        for o in reRecorded { ctx.insert(o) }
        try? ctx.save()

        // No duplicates: still exactly two, not four.
        #expect(observations(in: ctx).filter { $0.noteID == entry.id }.count == 2)
    }

    @Test func deleteObservationsScopedToNote() throws {
        let env = Env()
        let ctx = env.context
        let a = TranscriptEntry(text: "a", date: Date(), kind: .note)
        let b = TranscriptEntry(text: "b", date: Date(), kind: .note)
        ctx.insert(a); ctx.insert(b)
        ctx.insert(CoachObservation(noteID: a.id, lensRaw: Lens.grammar.rawValue, originRaw: "llm"))
        ctx.insert(CoachObservation(noteID: b.id, lensRaw: Lens.grammar.rawValue, originRaw: "llm"))
        try? ctx.save()

        TranscriptDeletion.deleteObservations(noteID: a.id, in: ctx)

        let remaining = observations(in: ctx)
        #expect(remaining.count == 1)
        #expect(remaining.first?.noteID == b.id)   // b's observation untouched
    }
}
