import Foundation
import Testing
@testable import HexCore

/// TDD for RC-6: a never-punishing streak — consecutive days with ≥1 review.
struct StreakCalculatorTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    @Test
    func firstReviewStartsAtOne() {
        let s = StreakCalculator.recording(StreakState(), reviewedOn: day("2026-06-01 09:00"), calendar: cal)
        #expect(s.current == 1)
        #expect(s.best == 1)
    }

    @Test
    func sameDayDoesNotIncrement() {
        var s = StreakCalculator.recording(StreakState(), reviewedOn: day("2026-06-01 09:00"), calendar: cal)
        s = StreakCalculator.recording(s, reviewedOn: day("2026-06-01 22:00"), calendar: cal)
        #expect(s.current == 1)
    }

    @Test
    func consecutiveDaysIncrement() {
        var s = StreakCalculator.recording(StreakState(), reviewedOn: day("2026-06-01 09:00"), calendar: cal)
        s = StreakCalculator.recording(s, reviewedOn: day("2026-06-02 08:00"), calendar: cal)
        s = StreakCalculator.recording(s, reviewedOn: day("2026-06-03 23:00"), calendar: cal)
        #expect(s.current == 3)
        #expect(s.best == 3)
    }

    @Test
    func gapResetsToOneButKeepsBest() {
        var s = StreakCalculator.recording(StreakState(), reviewedOn: day("2026-06-01 09:00"), calendar: cal)
        s = StreakCalculator.recording(s, reviewedOn: day("2026-06-02 09:00"), calendar: cal)
        s = StreakCalculator.recording(s, reviewedOn: day("2026-06-02 09:00"), calendar: cal)
        let best = s.best
        // Skip a day → reset.
        s = StreakCalculator.recording(s, reviewedOn: day("2026-06-05 09:00"), calendar: cal)
        #expect(s.current == 1)
        #expect(s.best == best) // best never drops
    }
}
