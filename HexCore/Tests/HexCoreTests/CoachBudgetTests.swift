import Foundation
import Testing
@testable import HexCore

/// TDD for CE-5: the monthly budget cap that bounds BYOK analysis spend.
/// Pure logic — no Date(), no I/O — so the cap behavior is deterministic.
struct CoachBudgetTests {
    // MARK: canAnalyze

    @Test func uncappedAlwaysAllows() {
        let budget = CoachBudget(monthlyCapUSD: nil)
        #expect(budget.canAnalyze(spentThisMonth: 0))
        #expect(budget.canAnalyze(spentThisMonth: 9_999))
    }

    @Test func underCapAllows() {
        let budget = CoachBudget(monthlyCapUSD: 5)
        #expect(budget.canAnalyze(spentThisMonth: 0))
        #expect(budget.canAnalyze(spentThisMonth: 4.99))
    }

    @Test func atOrOverCapBlocks() {
        let budget = CoachBudget(monthlyCapUSD: 5)
        #expect(!budget.canAnalyze(spentThisMonth: 5))
        #expect(!budget.canAnalyze(spentThisMonth: 5.01))
        #expect(!budget.canAnalyze(spentThisMonth: 100))
    }

    // MARK: remaining

    @Test func uncappedRemainingIsNil() {
        let budget = CoachBudget(monthlyCapUSD: nil)
        #expect(budget.remaining(spentThisMonth: 3) == nil)
    }

    @Test func remainingReflectsSpend() {
        let budget = CoachBudget(monthlyCapUSD: 10)
        #expect(budget.remaining(spentThisMonth: 0) == 10)
        #expect(budget.remaining(spentThisMonth: 4) == 6)
    }

    @Test func remainingClampsToZero() {
        let budget = CoachBudget(monthlyCapUSD: 10)
        #expect(budget.remaining(spentThisMonth: 10) == 0)
        #expect(budget.remaining(spentThisMonth: 12) == 0)
    }

    // MARK: monthKey

    @Test func monthKeyFormat() {
        let date = Date(timeIntervalSince1970: 1_782_000_000)
        let key = CoachBudget.monthKey(for: date)
        #expect(key.count == 7)
        // yyyy-MM
        let parts = key.split(separator: "-")
        #expect(parts.count == 2)
        #expect(parts[0].count == 4)
        #expect(parts[1].count == 2)
    }

    @Test func monthKeyDiffersAcrossMonths() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 15
        let jan = cal.date(from: comps)!
        comps.month = 2
        let feb = cal.date(from: comps)!
        #expect(CoachBudget.monthKey(for: jan) != CoachBudget.monthKey(for: feb))
        #expect(CoachBudget.monthKey(for: jan) == "2026-01")
        #expect(CoachBudget.monthKey(for: feb) == "2026-02")
    }

    @Test func monthKeyEqualWithinMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 1
        let early = cal.date(from: comps)!
        comps.day = 28
        let late = cal.date(from: comps)!
        #expect(CoachBudget.monthKey(for: early) == CoachBudget.monthKey(for: late))
    }
}
