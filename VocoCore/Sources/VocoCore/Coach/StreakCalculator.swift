import Foundation

/// A never-punishing review streak (RC-6): consecutive calendar days with at
/// least one review/shadow. `best` is the all-time high and never drops.
public struct StreakState: Codable, Sendable, Equatable {
    public var current: Int
    public var best: Int
    /// Start-of-day of the most recent review.
    public var lastReviewDay: Date?

    public init(current: Int = 0, best: Int = 0, lastReviewDay: Date? = nil) {
        self.current = current
        self.best = best
        self.lastReviewDay = lastReviewDay
    }
}

public enum StreakCalculator {
    /// Record a review on `date`. Same calendar day → unchanged; the next day →
    /// +1; a gap of two or more days → reset to 1. `best` only ever rises.
    public static func recording(
        _ state: StreakState,
        reviewedOn date: Date,
        calendar: Calendar = .current
    ) -> StreakState {
        let today = calendar.startOfDay(for: date)
        var next = state

        if let last = state.lastReviewDay {
            let lastDay = calendar.startOfDay(for: last)
            let gap = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            switch gap {
            case 0: break                    // same day — no change
            case 1: next.current += 1        // consecutive
            default: next.current = 1        // gap (or clock moved back) — reset
            }
        } else {
            next.current = 1
        }

        next.lastReviewDay = today
        next.best = max(next.best, next.current)
        return next
    }
}
