//
//  CoachProgress.swift
//  HexIOS
//
//  RC-6 progress/rewards: a never-punishing review streak plus a read-through to
//  the LearnerProfile for per-lens levels and "wins" (mastered patterns). Streak
//  lives in the App Group; levels/wins come from the same profile the engine
//  writes. Nothing here can decrease in a way that reads as a downgrade.
//

import Foundation
import HexCore
import Observation

@MainActor
@Observable
final class CoachProgress {
    private let defaults = UserDefaults(suiteName: HexAppGroup.identifier) ?? .standard
    @ObservationIgnored private static let streakKey = "hex.coach.streak"

    private(set) var streak: StreakState

    init() {
        if let data = defaults.data(forKey: Self.streakKey),
           let saved = try? JSONDecoder().decode(StreakState.self, from: data) {
            streak = saved
        } else {
            streak = StreakState()
        }
    }

    /// Count today toward the streak (called when the user reviews/shadows a card).
    func recordReview(now: Date = Date()) {
        streak = StreakCalculator.recording(streak, reviewedOn: now)
        if let data = try? JSONEncoder().encode(streak) {
            defaults.set(data, forKey: Self.streakKey)
        }
    }

    /// The LearnerProfile the engine maintains (levels + mastered patterns).
    func loadProfile() -> LearnerProfile {
        let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HexAppGroup.identifier)?
            .appendingPathComponent("Coach", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
        return LearnerProfileStore(url: dir.appendingPathComponent("profile.json")).load()
    }

    /// The CI-12 cross-lens progress roll-up: per-lens levels + trends, a
    /// pronunciation GOP summary, mastered-pattern "wins", and the streak.
    ///
    /// `pronunciationCorpus` is the set of per-note pronunciation summaries already
    /// persisted with transcripts (CI-3); the caller (which holds the SwiftData
    /// query) gathers them — we only READ existing data, never add persistence.
    /// The trend/aggregation math lives in the pure `ProgressSummary` helper.
    func summary(pronunciationCorpus: [PronunciationSignals] = []) -> ProgressSummary {
        ProgressSummary.make(
            profile: loadProfile(),
            streak: streak,
            pronunciationCorpus: pronunciationCorpus
        )
    }
}
