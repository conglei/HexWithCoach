import Foundation

/// A monthly spending cap for BYOK Coach analysis (CE-5). Pure and Sendable so
/// the cap decision is deterministic and unit-testable; the calling service owns
/// persistence and the per-month spend accounting.
public struct CoachBudget: Sendable, Equatable {
    /// The monthly ceiling in USD. `nil` means uncapped.
    public var monthlyCapUSD: Double?

    public init(monthlyCapUSD: Double? = nil) {
        self.monthlyCapUSD = monthlyCapUSD
    }

    /// True when uncapped, or when this month's spend is still below the cap.
    public func canAnalyze(spentThisMonth: Double) -> Bool {
        guard let cap = monthlyCapUSD else { return true }
        return spentThisMonth < cap
    }

    /// USD left under the cap this month, clamped at 0. `nil` when uncapped.
    public func remaining(spentThisMonth: Double) -> Double? {
        guard let cap = monthlyCapUSD else { return nil }
        return max(0, cap - spentThisMonth)
    }

    /// "yyyy-MM" for the given date, via a fixed Gregorian calendar so the
    /// per-month spend bucket key is stable and locale-independent.
    public static func monthKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
}
