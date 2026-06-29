#if DEBUG

import Foundation
import SwiftData
import Testing
import VocoCore
@testable import Voco

/// Behavior spec for the DEBUG-only SEED harness (`DebugSeed`). Verifies that a
/// single `seed(into:)` call produces a non-empty, internally-consistent corpus in
/// the live SwiftData container — enough that History, the Review feed, and the
/// Coach screens all have material to render.
///
/// The file-backed Coach stores (LearnerProfile / CoachSnapshots) write to the App
/// Group container in the real app; these tests focus on the SwiftData side, which
/// is the part wired to the in-memory test container. The seed call must not throw
/// or trap even when the App Group is unavailable in the test host.
@MainActor
@Suite struct DebugSeedTests {

    /// Holds the `ModelContainer` alive for the test's lifetime — dropping it while
    /// keeping only the context dangles the store and traps SwiftData on save.
    @MainActor
    private final class Env {
        let container: ModelContainer
        let context: ModelContext

        init() {
            container = try! ModelContainer(
                for: TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
                CoachObservation.self, PracticeItem.self, PracticeAttempt.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = container.mainContext
        }
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: Notes

    @Test func seedsAtLeastTenNotesAcrossKinds() {
        let env = Env()
        DebugSeed.seed(into: env.context)

        let notes = fetch(TranscriptEntry.self, in: env.context)
        #expect(notes.count >= 10)
        // Both kinds are represented.
        #expect(notes.contains { $0.kind == .note })
        #expect(notes.contains { $0.kind == .dictation })
        // Spread across more than one day.
        let days = Set(notes.map { Calendar.current.startOfDay(for: $0.date) })
        #expect(days.count >= 3)
    }

    // MARK: Coach cards across lenses

    @Test func seedsCardsAcrossAllFiveLenses() {
        let env = Env()
        DebugSeed.seed(into: env.context)

        let cards = fetch(CoachCardEntity.self, in: env.context)
        #expect(cards.count >= 5)

        let lenses = Set(cards.map(\.lens))
        #expect(lenses.count >= 3)            // spec floor
        #expect(lenses == Set(Lens.allCases)) // we actually cover all five

        // Some are .new (feed), at least one .saved (phrasebook/summary screens).
        #expect(cards.contains { $0.status == .new })
        #expect(cards.contains { $0.status == .saved })

        // Practice material is populated on improvement cards.
        #expect(cards.contains { ($0.practiceText?.isEmpty == false) })
        #expect(cards.contains { ($0.nativeRewrite?.isEmpty == false) })

        // Cards link to seeded notes.
        let noteIDs = Set(fetch(TranscriptEntry.self, in: env.context).map(\.id))
        let linked = cards.compactMap(\.transcriptID).filter(noteIDs.contains)
        #expect(!linked.isEmpty)
    }

    // MARK: Observation clusters

    @Test func seedsObservationClustersWithFrequencyAndGOP() {
        let env = Env()
        DebugSeed.seed(into: env.context)

        let obs = fetch(CoachObservation.self, in: env.context)
        #expect(obs.count >= 20)

        // A frequent LLM-lane pattern cluster (≥ several rows for one key).
        let dropArticles = obs.filter { $0.patternKey == "drop-articles" }
        #expect(dropArticles.count >= 8)

        // Per-word objective GOP rows exist with scores.
        let withGOP = obs.filter { $0.word != nil && $0.gop != nil }
        #expect(!withGOP.isEmpty)
        #expect(withGOP.contains { $0.word == "thorough" })

        // patternKeys match the seeded RecurringPattern keys (consistency).
        #expect(obs.contains { $0.patternKey == "overuse-basically" })
    }

    // MARK: Practice

    @Test func seedsPracticeItemsWithAttempts() {
        let env = Env()
        DebugSeed.seed(into: env.context)

        let items = fetch(PracticeItem.self, in: env.context)
        #expect(items.count >= 2)
        #expect(items.contains { !$0.attempts.isEmpty })
    }

    // MARK: Idempotency

    @Test func reseedingDoesNotDuplicateNotes() {
        let env = Env()
        DebugSeed.seed(into: env.context)
        let firstCount = fetch(TranscriptEntry.self, in: env.context).count

        DebugSeed.seed(into: env.context)
        let secondCount = fetch(TranscriptEntry.self, in: env.context).count

        #expect(secondCount == firstCount)
    }

    // MARK: Launch flag

    @Test func launchSeedIsNoOpWithoutFlag() {
        let env = Env()
        // No VOCO_SEED in the test environment, so this must not seed.
        DebugSeed.seedIfRequestedAtLaunch(into: env.context)
        #expect(fetch(TranscriptEntry.self, in: env.context).isEmpty)
    }
}

#endif
