import Foundation
import SwiftData
import Testing
import VocoCore
@testable import Voco

/// GUARD invariant: the canonical `@Model` list (`TranscriptStore.allModelTypes`)
/// must be registered in *every* `ModelContainer` site.
///
/// A whole class of bugs came from a model type being left out of one container
/// configuration: a missing registration is a launch crash (the live store) or an
/// empty SwiftUI preview (e.g. the OnboardingView preview once omitted
/// `CoachCardEntity`). The list used to be duplicated across ~6 sites and reviewers
/// eyeballed each one. Now there is a single source of truth and this test enforces
/// it: every container configuration's schema is asserted to contain exactly the
/// entities derived from `allModelTypes`.
///
/// Because the expected entity set is *derived from* `allModelTypes` (never an
/// inline literal), adding a new `@Model` without adding it to `allModelTypes`
/// makes the type unreachable from these containers and fails this suite — instead
/// of shipping a registration gap.
///
/// Containers are retained for the lifetime of each test: holding only a
/// `ModelContext` while its container deallocates dangles the store and SIGTRAPs
/// SwiftData on the next access.
@MainActor
@Suite struct SchemaRegistrationTests {

    /// The canonical entity names, derived from the single source of truth.
    private var expectedEntityNames: Set<String> {
        Set(TranscriptStore.schema.entities.map(\.name))
    }

    /// Sanity: the canonical list isn't empty and matches the six known models.
    /// This pins the source of truth so an accidental deletion is caught too.
    @Test func canonicalListIsComplete() {
        let names = expectedEntityNames
        #expect(TranscriptStore.allModelTypes.count == 6)
        #expect(names == [
            "TranscriptEntry",
            "TranscriptAnalysis",
            "CoachCardEntity",
            "CoachObservation",
            "PracticeItem",
            "PracticeAttempt",
        ])
    }

    /// Assert a freshly built container's schema contains exactly the canonical
    /// entity set. The container is returned to the caller so it stays alive.
    private func assertContainerHasAllModels(
        _ make: () -> ModelContainer,
        _ label: String
    ) -> ModelContainer {
        let container = make()
        let actual = Set(container.schema.entities.map(\.name))
        #expect(
            actual == expectedEntityNames,
            "\(label) schema is missing models: \(expectedEntityNames.subtracting(actual)); extra: \(actual.subtracting(expectedEntityNames))"
        )
        return container
    }

    /// The live container factory (`makeContainer`) must register every model.
    /// Whichever configuration it lands on (CloudKit, local, or in-memory), the
    /// schema is identical because all three are built from `allModelTypes`.
    @Test func makeContainerRegistersAllModels() {
        let container = assertContainerHasAllModels(
            { TranscriptStore.makeContainer() },
            "TranscriptStore.makeContainer()"
        )
        withExtendedLifetime(container) {}
    }

    /// The in-memory configuration used by SwiftUI previews and test fixtures.
    /// This is the configuration the OnboardingView / ContentView previews use.
    @Test func inMemoryContainerRegistersAllModels() {
        let container = assertContainerHasAllModels(
            {
                try! ModelContainer(
                    for: TranscriptStore.schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            },
            "in-memory ModelContainer(for: TranscriptStore.schema)"
        )
        withExtendedLifetime(container) {}
    }

    /// The local (non-CloudKit) on-disk configuration `makeContainer` falls back to.
    @Test func localContainerRegistersAllModels() {
        let container = assertContainerHasAllModels(
            {
                try! ModelContainer(
                    for: TranscriptStore.schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                )
            },
            "local ModelContainer(for: TranscriptStore.schema)"
        )
        withExtendedLifetime(container) {}
    }
}
