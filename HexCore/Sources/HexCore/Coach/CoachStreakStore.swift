//
//  CoachStreakStore.swift
//  HexCore
//
//  One home for the review streak's persistence. The app writes it (CoachProgress);
//  the Home Screen widget reads it cross-process. Keeping the key + codec here
//  means neither side hardcodes the storage format.
//

import Foundation

public enum CoachStreakStore {
    static let key = "hex.coach.streak"

    public static func load(appGroupIdentifier: String = HexAppGroup.identifier) -> StreakState {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: key),
              let state = try? JSONDecoder().decode(StreakState.self, from: data)
        else { return StreakState() }
        return state
    }

    public static func save(_ state: StreakState, appGroupIdentifier: String = HexAppGroup.identifier) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: key)
    }
}

/// Everything the Home Screen widget needs, read from the App Group in one shot.
/// Pure value type so the Provider stays trivial and this stays unit-testable.
public struct HomeWidgetSnapshot: Sendable, Equatable {
    /// Whether the keyboard has run with Full Access at least once — our only
    /// available signal that it's set up. iOS exposes no API to query "is the
    /// keyboard enabled right now", so this is a heuristic, not ground truth.
    public var keyboardReady: Bool
    /// Current never-punishing review streak in days.
    public var streak: Int

    public init(keyboardReady: Bool, streak: Int) {
        self.keyboardReady = keyboardReady
        self.streak = streak
    }

    public static func current(appGroupIdentifier: String = HexAppGroup.identifier) -> HomeWidgetSnapshot {
        HomeWidgetSnapshot(
            keyboardReady: KeyboardPresence.lastActive(appGroupIdentifier: appGroupIdentifier) != nil,
            streak: CoachStreakStore.load(appGroupIdentifier: appGroupIdentifier).current
        )
    }
}
