//
//  SyncStore.swift
//  VocoEngine (shared: macOS VocoMac + iOS Voco)
//
//  Shared CloudKit-capable `ModelContainer` factory + sync preferences (MC-R2).
//  Both app targets build the same store from one schema: a CloudKit-synced
//  container when iCloud sync is enabled, falling back to local-only (then
//  in-memory) otherwise. Depends only on VocoCore (HexAppGroup) +
//  Foundation/SwiftData, so it's UIKit/AppKit-free and compiles into both modules.
//

import Foundation
import SwiftData
import VocoCore

/// User-controllable sync preferences, persisted in the App Group.
enum SyncPreferences {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: HexAppGroup.identifier) }

    /// Whether history should sync via iCloud. Read once at launch to pick the
    /// store configuration (changing it takes effect on next launch).
    static var iCloudEnabled: Bool {
        get { defaults?.object(forKey: "hex.iCloudEnabled") as? Bool ?? true }
        set { defaults?.set(newValue, forKey: "hex.iCloudEnabled") }
    }

    /// Forward-looking: sync audio recordings too (audio isn't persisted yet).
    static var syncAudio: Bool {
        get { defaults?.bool(forKey: "hex.syncAudio") ?? false }
        set { defaults?.set(newValue, forKey: "hex.syncAudio") }
    }
}

/// Shared factory for the note `ModelContainer`, used by both app targets.
enum SyncStore {
    /// The CloudKit container both apps target, pinned explicitly so the iOS and
    /// macOS bundle IDs merge into the *same* container (MC-2). `.automatic` would
    /// derive it per-app from entitlements; pinning removes the ambiguity. Must
    /// match `com.apple.developer.icloud-container-identifiers` in both
    /// `Voco.entitlements` and `VocoMac.entitlements`.
    static let cloudContainerID = "iCloud.co.stonefrontier.voco"

    /// Every `@Model` type in the shared Phase-3 schema. Both app targets register
    /// exactly this set so the local store and the CloudKit mirror stay consistent.
    ///
    /// This is the single canonical model list. iOS re-exports it via
    /// `TranscriptStore.allModelTypes`, and the `SchemaRegistrationTests` GUARD
    /// invariant pins this set so any container built from a different list fails.
    static let schemaTypes: [any PersistentModel.Type] = [
        TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
        CoachObservation.self, PracticeItem.self, PracticeAttempt.self,
    ]

    /// The canonical `Schema` built from `schemaTypes`, for sites that want a
    /// `Schema` rather than the variadic type list.
    static var schema: Schema { Schema(schemaTypes) }

    /// Build the model container. Prefers the CloudKit-synced store; falls back
    /// to a local-only store if CloudKit is unavailable (e.g. no iCloud account),
    /// and finally to an in-memory store so the app still runs.
    @MainActor
    static func makeContainer() -> ModelContainer {
        let schema = self.schema
        if SyncPreferences.iCloudEnabled,
           let cloud = try? ModelContainer(
               for: schema,
               configurations: ModelConfiguration(cloudKitDatabase: .private(cloudContainerID))
           ) {
            return cloud
        }
        if let local = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(cloudKitDatabase: .none)
        ) {
            return local
        }
        // In-memory last resort so the app still runs.
        return try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
