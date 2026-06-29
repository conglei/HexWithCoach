import Foundation
import Testing
@testable import VocoCore

struct CoachSnapshotTests {

    // A fixed UTC calendar so week boundaries are deterministic across machines.
    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        return utc.date(from: comps)!
    }

    private static func snap(
        _ id: UUID = UUID(),
        on date: Date,
        fillers: Double = 0,
        wpm: Double = 0,
        gop: Double? = nil
    ) -> CoachSnapshot {
        CoachSnapshot(
            noteID: id, date: date, durationSec: 60, wordCount: 100,
            fillersPerMinute: fillers, wordsPerMinute: wpm, longPauseRate: 0,
            restartCount: 0, hasPauseStats: false, overallGOP: gop
        )
    }

    // MARK: - Init from signals

    @Test func initFromSignalsMapsFields() {
        let fluency = FluencySignals(
            wordsPerMinute: 150, wordCount: 100, durationSec: 40,
            fillersPerMinute: 6, fillerCount: 4, restartCount: 2,
            longPauseRate: 0.2, hasPauseStats: true
        )
        let id = UUID()
        let s = CoachSnapshot(noteID: id, date: Self.date(2026, 4, 1), fluency: fluency, pronunciation: nil)
        #expect(s.noteID == id)
        #expect(s.wordsPerMinute == 150)
        #expect(s.fillersPerMinute == 6)
        #expect(s.restartCount == 2)
        #expect(s.longPauseRate == 0.2)
        #expect(s.hasPauseStats)
        #expect(s.overallGOP == nil)
    }

    @Test func gopZeroBecomesNil() {
        // 0 is the "no measurement" sentinel — must not read as a perfect score.
        let pron = PronunciationSignals(overallGOP: 0, perPhoneme: [], worstWords: [])
        let s = CoachSnapshot(noteID: UUID(), date: Self.date(2026, 4, 1),
                              fluency: FluencySignals(), pronunciation: pron)
        #expect(s.overallGOP == nil)
    }

    @Test func negativeGOPIsKept() {
        let pron = PronunciationSignals(overallGOP: -0.7, perPhoneme: [], worstWords: [])
        let s = CoachSnapshot(noteID: UUID(), date: Self.date(2026, 4, 1),
                              fluency: FluencySignals(), pronunciation: pron)
        #expect(s.overallGOP == -0.7)
    }

    // MARK: - Log

    @Test func upsertReplacesByNoteIDAndStaysSorted() {
        let id = UUID()
        var log = CoachSnapshotLog()
        log.upsert(Self.snap(id, on: Self.date(2026, 4, 10), fillers: 12))
        log.upsert(Self.snap(on: Self.date(2026, 4, 1), fillers: 3))
        // Re-analyze the first note → replace, not duplicate.
        log.upsert(Self.snap(id, on: Self.date(2026, 4, 10), fillers: 5))

        #expect(log.count == 2)
        #expect(log.snapshots.map(\.date) == [Self.date(2026, 4, 1), Self.date(2026, 4, 10)])
        #expect(log.snapshots.last?.fillersPerMinute == 5)
    }

    @Test func sinceFiltersByDate() {
        var log = CoachSnapshotLog()
        log.upsert(Self.snap(on: Self.date(2026, 4, 1)))
        log.upsert(Self.snap(on: Self.date(2026, 4, 20)))
        #expect(log.since(Self.date(2026, 4, 10)).count == 1)
    }

    // MARK: - Weekly rollup

    @Test func weeklyGroupsAndAveragesIgnoringNilGOP() {
        var log = CoachSnapshotLog()
        // Two notes in the week of Mon Apr 6, one with GOP, one without.
        log.upsert(Self.snap(on: Self.date(2026, 4, 6), fillers: 10, wpm: 200, gop: -1.0))
        log.upsert(Self.snap(on: Self.date(2026, 4, 8), fillers: 6, wpm: 160, gop: nil))
        // One note the following week.
        log.upsert(Self.snap(on: Self.date(2026, 4, 14), fillers: 2, wpm: 150, gop: -0.4))

        let weeks = log.weekly(calendar: Self.utc)
        #expect(weeks.count == 2)

        let first = weeks[0]
        #expect(first.noteCount == 2)
        #expect(first.meanFillersPerMinute == 8)        // (10 + 6) / 2
        #expect(first.meanWordsPerMinute == 180)        // (200 + 160) / 2
        #expect(first.meanGOP == -1.0)                  // only the one note with GOP
        #expect(first.totalDurationSec == 120)

        let second = weeks[1]
        #expect(second.noteCount == 1)
        #expect(second.meanGOP == -0.4)
        // Oldest week first.
        #expect(weeks[0].weekStart < weeks[1].weekStart)
    }

    @Test func weeklyEmptyLogIsEmpty() {
        #expect(CoachSnapshotLog().weekly(calendar: Self.utc).isEmpty)
    }

    // MARK: - Store round-trip

    @Test func storeRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoachSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CoachSnapshotStore(url: dir.appendingPathComponent("snapshots.json"))

        #expect(store.load().isEmpty) // missing file → empty, not a crash

        let a = Self.snap(on: Self.date(2026, 4, 1), fillers: 9, gop: -0.5)
        try store.record(a)
        try store.record(Self.snap(on: Self.date(2026, 4, 8), fillers: 4))

        let reloaded = store.load()
        #expect(reloaded.count == 2)
        #expect(reloaded.snapshots.first?.fillersPerMinute == 9)
        #expect(reloaded.snapshots.first?.overallGOP == -0.5)
    }

    @Test func storeRecordUpsertsByNoteID() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoachSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CoachSnapshotStore(url: dir.appendingPathComponent("snapshots.json"))

        let id = UUID()
        try store.record(Self.snap(id, on: Self.date(2026, 4, 1), fillers: 12))
        try store.record(Self.snap(id, on: Self.date(2026, 4, 1), fillers: 3))

        let reloaded = store.load()
        #expect(reloaded.count == 1)
        #expect(reloaded.snapshots.first?.fillersPerMinute == 3)
    }

    // MARK: - Remove (HS-3 cascade delete)

    @Test func logRemoveDropsOnlyThatNote() {
        let keep = UUID()
        let drop = UUID()
        var log = CoachSnapshotLog([
            Self.snap(keep, on: Self.date(2026, 4, 1)),
            Self.snap(drop, on: Self.date(2026, 4, 8)),
        ])

        #expect(log.remove(noteID: drop) == true)
        #expect(log.count == 1)
        #expect(log.snapshots.first?.noteID == keep)
        // Removing a note that isn't present reports no change.
        #expect(log.remove(noteID: UUID()) == false)
        #expect(log.count == 1)
    }

    @Test func storeRemovePersistsAndIsNoOpWhenAbsent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoachSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CoachSnapshotStore(url: dir.appendingPathComponent("snapshots.json"))

        let keep = UUID()
        let drop = UUID()
        try store.record(Self.snap(keep, on: Self.date(2026, 4, 1)))
        try store.record(Self.snap(drop, on: Self.date(2026, 4, 8)))

        try store.remove(noteID: drop)
        var reloaded = store.load()
        #expect(reloaded.count == 1)
        #expect(reloaded.snapshots.first?.noteID == keep)

        // Removing an absent note must not throw or corrupt the log.
        try store.remove(noteID: UUID())
        reloaded = store.load()
        #expect(reloaded.count == 1)
    }
}
