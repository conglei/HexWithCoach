import Foundation
import SwiftData
import Testing
import VocoCore
@testable import Voco

/// Behavior spec for the DM-2 observation log: every coaching finding is persisted
/// as an append-only, dated `CoachObservation` *before* curation, so cross-note
/// coaching (frequency over time, per-word GOP trends, evidence trails) becomes a
/// query rather than something reconstructed from transient insights.
///
/// These cover the two on-device write paths — the verified-insight helper
/// (`recordObservations`) and the objective per-word GOP helper
/// (`recordWordObservations`). The live Gemini LLM path is intentionally NOT
/// exercised (it needs network + a key); the helpers are tested directly with
/// synthetic insights / pronunciation results.
@MainActor
@Suite struct CoachObservationLogTests {

    /// A test environment that keeps the `ModelContainer` alive for the duration of
    /// the test. (Holding only the `ModelContext` while the container deallocates
    /// dangles the store and traps SwiftData on the next save.)
    @MainActor
    private final class Env {
        let container: ModelContainer
        let context: ModelContext
        let service: CoachService

        init() {
            container = try! ModelContainer(
                for: TranscriptStore.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = container.mainContext
            service = CoachService(modelContext: context, preferences: CoachPreferences())
        }
    }

    private func observations(in context: ModelContext) -> [CoachObservation] {
        (try? context.fetch(FetchDescriptor<CoachObservation>())) ?? []
    }

    private func insight(
        lens: Lens, key: String, span: String, severity: Int, transcriptID: UUID
    ) -> CoachInsight {
        CoachInsight(
            transcriptID: transcriptID, lens: lens, key: key,
            summary: "s", rule: "r", originalSpan: span,
            nativeRewrite: "n", severity: severity
        )
    }

    // MARK: recordObservations (LLM lane)

    @Test func recordsOneRowPerInsightWithCorrectFields() {
        let env = Env()
        let date = Date(timeIntervalSinceReferenceDate: 12_345)
        let entry = TranscriptEntry(text: "hello world", date: date, kind: .note)
        env.context.insert(entry)

        let insights = [
            insight(lens: .grammar, key: "drop-articles", span: "go to store", severity: 3, transcriptID: entry.id),
            insight(lens: .lexis, key: "overuse-very", span: "very very good", severity: 2, transcriptID: entry.id),
        ]

        env.service.recordObservations(insights, for: entry, origin: .llm)
        try? env.context.save()

        let rows = observations(in: env.context)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.noteID == entry.id })
        #expect(rows.allSatisfy { $0.date == date })
        #expect(rows.allSatisfy { $0.origin == .llm })
        #expect(rows.allSatisfy { $0.originRaw == "llm" })

        let grammar = rows.first { $0.lensRaw == Lens.grammar.rawValue }
        #expect(grammar?.patternKey == "drop-articles")
        #expect(grammar?.span == "go to store")
        #expect(grammar?.severity == 3)
        #expect(grammar?.word == nil)
        #expect(grammar?.gop == nil)

        let lexis = rows.first { $0.lensRaw == Lens.lexis.rawValue }
        #expect(lexis?.patternKey == "overuse-very")
        #expect(lexis?.severity == 2)
    }

    @Test func recordObservationsIsAppendOnly() {
        let env = Env()
        let entry = TranscriptEntry(text: "x", date: Date(), kind: .note)
        env.context.insert(entry)

        env.service.recordObservations(
            [insight(lens: .grammar, key: "k1", span: "a", severity: 1, transcriptID: entry.id)],
            for: entry, origin: .llm
        )
        env.service.recordObservations(
            [insight(lens: .discourse, key: "k2", span: "b", severity: 4, transcriptID: entry.id)],
            for: entry, origin: .llm
        )
        try? env.context.save()

        // Each finding accumulates — nothing is overwritten.
        #expect(observations(in: env.context).count == 2)
    }

    @Test func emptyInsightsRecordNothing() {
        let env = Env()
        let entry = TranscriptEntry(text: "x", date: Date(), kind: .note)
        env.context.insert(entry)

        env.service.recordObservations([], for: entry, origin: .llm)
        try? env.context.save()

        #expect(observations(in: env.context).isEmpty)
    }

    // MARK: recordWordObservations (objective per-word GOP lane)

    @Test func recordsOneObjectiveRowPerWordWithGOP() {
        let env = Env()
        let date = Date(timeIntervalSinceReferenceDate: 7_000)
        let entry = TranscriptEntry(text: "comfortable schedule", date: date, kind: .note)
        env.context.insert(entry)

        let result = PronunciationResult(words: [
            WordScore(word: "comfortable", phonemes: [
                PhonemeScore(symbol: "k", start: 0, end: 0.1, gop: -1.0),
                PhonemeScore(symbol: "ə", start: 0.1, end: 0.2, gop: -3.0),
            ]),
            WordScore(word: "schedule", phonemes: [
                PhonemeScore(symbol: "s", start: 0.2, end: 0.3, gop: -0.5),
            ]),
        ])

        env.service.recordWordObservations(result, for: entry)
        try? env.context.save()

        let rows = observations(in: env.context)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.origin == .objective })
        #expect(rows.allSatisfy { $0.lensRaw == Lens.pronunciation.rawValue })
        #expect(rows.allSatisfy { $0.noteID == entry.id })
        #expect(rows.allSatisfy { $0.date == date })
        #expect(rows.allSatisfy { $0.span == nil && $0.patternKey == nil })

        let comfortable = rows.first { $0.word == "comfortable" }
        #expect(comfortable != nil)
        // Mean of -1.0 and -3.0.
        #expect(comfortable?.gop == -2.0)

        let schedule = rows.first { $0.word == "schedule" }
        #expect(schedule?.gop == -0.5)
    }

    // MARK: Per-word cross-note query

    @Test func perWordQueryReturnsDatedGOPsAcrossNotes() {
        let env = Env()
        let day1 = Date(timeIntervalSinceReferenceDate: 0)
        let day2 = Date(timeIntervalSinceReferenceDate: 86_400)

        let note1 = TranscriptEntry(text: "comfortable", date: day1, kind: .note)
        let note2 = TranscriptEntry(text: "comfortable", date: day2, kind: .note)
        env.context.insert(note1)
        env.context.insert(note2)

        env.service.recordWordObservations(
            PronunciationResult(words: [WordScore(word: "comfortable", phonemes: [
                PhonemeScore(symbol: "k", start: 0, end: 0.1, gop: -4.0),
            ])]),
            for: note1
        )
        env.service.recordWordObservations(
            PronunciationResult(words: [WordScore(word: "comfortable", phonemes: [
                PhonemeScore(symbol: "k", start: 0, end: 0.1, gop: -1.0),
            ])]),
            for: note2
        )
        try? env.context.save()

        // Query the per-word GOP trend for "comfortable" across notes, dated.
        let target = "comfortable"
        let pronunciationRaw = Lens.pronunciation.rawValue
        let descriptor = FetchDescriptor<CoachObservation>(
            predicate: #Predicate { $0.word == target && $0.lensRaw == pronunciationRaw },
            sortBy: [SortDescriptor(\.date)]
        )
        let trend = (try? env.context.fetch(descriptor)) ?? []

        #expect(trend.count == 2)
        #expect(trend.map(\.date) == [day1, day2])
        #expect(trend.map { $0.gop ?? 0 } == [-4.0, -1.0])   // improving over time
    }

    @Test func fetchByNoteIDReturnsOnlyThatNotesObservations() {
        let env = Env()
        let noteA = TranscriptEntry(text: "a", date: Date(), kind: .note)
        let noteB = TranscriptEntry(text: "b", date: Date(), kind: .note)
        env.context.insert(noteA)
        env.context.insert(noteB)

        env.service.recordWordObservations(
            PronunciationResult(words: [WordScore(word: "alpha", phonemes: [
                PhonemeScore(symbol: "a", start: 0, end: 0.1, gop: -2.0),
            ])]),
            for: noteA
        )
        env.service.recordWordObservations(
            PronunciationResult(words: [
                WordScore(word: "beta", phonemes: [PhonemeScore(symbol: "b", start: 0, end: 0.1, gop: -1.0)]),
                WordScore(word: "gamma", phonemes: [PhonemeScore(symbol: "g", start: 0, end: 0.1, gop: -1.0)]),
            ]),
            for: noteB
        )
        try? env.context.save()

        let aID = noteA.id
        let descriptor = FetchDescriptor<CoachObservation>(
            predicate: #Predicate { $0.noteID == aID }
        )
        let aRows = (try? env.context.fetch(descriptor)) ?? []
        #expect(aRows.count == 1)
        #expect(aRows.first?.word == "alpha")
    }
}
