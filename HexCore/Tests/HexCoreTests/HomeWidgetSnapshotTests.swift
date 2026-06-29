import Foundation
import Testing
@testable import HexCore

/// The Home widget reads keyboard-readiness + streak straight from the App Group.
/// These cover the round-trip through a private UserDefaults suite so the widget
/// and app agree on storage without hitting the real shared container.
struct HomeWidgetSnapshotTests {
    /// A throwaway suite so tests don't touch the real App Group / standard defaults.
    private func suite(_ name: String) -> String {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        return name
    }

    @Test
    func streakRoundTripsThroughTheStore() {
        let group = suite("test.voco.streak.roundtrip")
        CoachStreakStore.save(StreakState(current: 7, best: 9), appGroupIdentifier: group)
        #expect(CoachStreakStore.load(appGroupIdentifier: group).current == 7)
    }

    @Test
    func missingStreakDefaultsToZero() {
        let group = suite("test.voco.streak.empty")
        #expect(CoachStreakStore.load(appGroupIdentifier: group).current == 0)
    }

    @Test
    func keyboardNotReadyUntilItHasBeenActive() {
        let group = suite("test.voco.snapshot.cold")
        let snap = HomeWidgetSnapshot.current(appGroupIdentifier: group)
        #expect(snap.keyboardReady == false)
        #expect(snap.streak == 0)
    }

    @Test
    func snapshotReflectsPresenceAndStreak() {
        let group = suite("test.voco.snapshot.warm")
        KeyboardPresence.markActive(appGroupIdentifier: group)
        CoachStreakStore.save(StreakState(current: 4, best: 4), appGroupIdentifier: group)
        let snap = HomeWidgetSnapshot.current(appGroupIdentifier: group)
        #expect(snap.keyboardReady == true)
        #expect(snap.streak == 4)
    }
}
