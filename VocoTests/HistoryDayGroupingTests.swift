import Foundation
import Testing
@testable import Voco

/// Behavior spec for `HistoryDayGrouping.grouped` (HS-5).
///
/// The History list buckets a fetched window into day sections. Two ordering
/// guarantees matter for the UI and were the subject of the HS-5 day-header
/// placement bug:
///   • Day sections are newest-first (so "Today" sits above older days).
///   • Within a day, entries are reverse-chronological — a later note (13:29)
///     must come *before* earlier ones (11:01, 09:11), and therefore render
///     under (below) the day header rather than appearing to float above it.
/// The helper re-sorts defensively, so even an out-of-order input window lands
/// correctly.
@Suite struct HistoryDayGroupingTests {
    /// A fixed UTC calendar so day boundaries are deterministic in CI.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.date(from: iso)!
    }

    private struct Item { let date: Date }

    @Test func groupsByDayNewestFirst() {
        let items = [
            Item(date: date("2026-06-27T10:00:00Z")),
            Item(date: date("2026-06-29T09:11:00Z")),
            Item(date: date("2026-06-28T12:00:00Z")),
        ]
        let groups = HistoryDayGrouping.grouped(items, date: \.date, calendar: calendar)
        let days = groups.map { calendar.component(.day, from: $0.day) }
        #expect(days == [29, 28, 27])
    }

    /// The exact HS-5 symptom: a later note must sort ABOVE earlier same-day
    /// notes, regardless of input order.
    @Test func reverseChronologicalWithinDayEvenWhenInputIsScrambled() {
        let items = [
            Item(date: date("2026-06-29T11:01:00Z")),
            Item(date: date("2026-06-29T09:11:00Z")),
            Item(date: date("2026-06-29T13:29:00Z")), // latest, arrives last
        ]
        let groups = HistoryDayGrouping.grouped(items, date: \.date, calendar: calendar)
        #expect(groups.count == 1)
        let hours = groups[0].entries.map { calendar.component(.hour, from: $0.date) }
        #expect(hours == [13, 11, 9])
    }

    @Test func emptyInputProducesNoSections() {
        let groups = HistoryDayGrouping.grouped([Item](), date: \.date, calendar: calendar)
        #expect(groups.isEmpty)
    }

    @Test func sectionIdIsStartOfDay() {
        let items = [Item(date: date("2026-06-29T13:29:00Z"))]
        let groups = HistoryDayGrouping.grouped(items, date: \.date, calendar: calendar)
        #expect(groups[0].id == calendar.startOfDay(for: items[0].date))
    }
}
