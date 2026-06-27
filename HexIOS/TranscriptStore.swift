//
//  TranscriptStore.swift
//  HexIOS
//
//  Persistent, iCloud-synced transcript history (P4-2). SwiftData persists
//  locally (history survives relaunch) and, with the CloudKit container, syncs
//  across the user's devices automatically.
//

import Foundation
import HexCore
import SwiftData

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

@Model
final class TranscriptEntry {
    // CloudKit-backed SwiftData requires every attribute to have a default.
    /// Stable identity used to link Coach cards back to their source transcript.
    var id: UUID = UUID()
    var text: String = ""
    var date: Date = Date()
    var kindRaw: String = TranscriptKind.note.rawValue
    /// Host app for a cross-app dictation, when known. (Keyboard extensions can't
    /// read the host app, so this is usually nil for dictations for now.)
    var sourceAppName: String?
    /// Portable audio identity — a filename inside the App Group Audio dir, not an
    /// absolute path (RC-0 / data-model §4). nil if audio wasn't retained.
    var audioFilename: String?
    /// When the Coach analyzed this transcript. nil = still in the backlog (RC-2).
    var coachAnalyzedAt: Date?

    var kind: TranscriptKind { TranscriptKind(rawValue: kindRaw) ?? .note }

    init(text: String, date: Date, kind: TranscriptKind, sourceAppName: String? = nil, audioFilename: String? = nil) {
        self.text = text
        self.date = date
        self.kindRaw = kind.rawValue
        self.sourceAppName = sourceAppName
        self.audioFilename = audioFilename
    }
}

/// Lifecycle of a Coach card in the Review feed.
enum CoachCardStatus: String, Codable {
    case new        // unseen, in the feed
    case done       // user tapped "Got it"
    case dismissed  // user tapped "Not useful"
    case saved      // user saved it to the phrasebook (RC-5)
}

/// Persisted Review-feed card (RC-2/RC-3). A SwiftData mirror of the pure
/// `CoachCard` (HexCore) so the feed can `@Query` it and it syncs via CloudKit.
@Model
final class CoachCardEntity {
    var id: UUID = UUID()
    var kindRaw: String = CoachCardKind.improvement.rawValue
    var lensRaw: String = Lens.grammar.rawValue
    var key: String = ""
    var title: String = ""
    var detail: String = ""
    var originalSpan: String?
    var nativeRewrite: String?
    var transcriptID: UUID?
    var recurrenceNote: String?
    var createdAt: Date = Date()
    var statusRaw: String = CoachCardStatus.new.rawValue

    var kind: CoachCardKind { CoachCardKind(rawValue: kindRaw) ?? .improvement }
    var lens: Lens { Lens(rawValue: lensRaw) ?? .grammar }
    var status: CoachCardStatus {
        get { CoachCardStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue }
    }

    init(card: CoachCard) {
        id = card.id
        kindRaw = card.kind.rawValue
        lensRaw = card.lens.rawValue
        key = card.key
        title = card.title
        detail = card.detail
        originalSpan = card.originalSpan
        nativeRewrite = card.nativeRewrite
        transcriptID = card.transcriptID
        recurrenceNote = card.recurrenceNote
        createdAt = card.createdAt
    }
}

/// Persistent audio storage in the App Group container, so recordings survive
/// (the prototype deleted them) and are available for playback / shadowing.
enum AudioStore {
    @MainActor
    private static var directory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HexAppGroup.identifier)
        else { return nil }
        let dir = container.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Move a freshly-recorded temp file into persistent storage; returns its
    /// portable filename (or nil, having cleaned up, if retention isn't possible).
    @MainActor
    static func persist(_ tempURL: URL) -> String? {
        guard let directory else { try? FileManager.default.removeItem(at: tempURL); return nil }
        let filename = "\(UUID().uuidString).wav"
        let dest = directory.appendingPathComponent(filename)
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return filename
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }

    /// Resolve a stored filename to a URL if the file exists on this device.
    @MainActor
    static func url(for filename: String?) -> URL? {
        guard let filename, let directory else { return nil }
        let url = directory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

enum TranscriptStore {
    /// Build the model container. Prefers the CloudKit-synced store; falls back
    /// to a local-only store if CloudKit is unavailable (e.g. no iCloud account).
    @MainActor
    static func makeContainer() -> ModelContainer {
        if SyncPreferences.iCloudEnabled,
           let cloud = try? ModelContainer(
               for: TranscriptEntry.self, CoachCardEntity.self,
               configurations: ModelConfiguration(cloudKitDatabase: .automatic)
           ) {
            return cloud
        }
        if let local = try? ModelContainer(
            for: TranscriptEntry.self, CoachCardEntity.self,
            configurations: ModelConfiguration(cloudKitDatabase: .none)
        ) {
            return local
        }
        // In-memory last resort so the app still runs.
        return try! ModelContainer(
            for: TranscriptEntry.self, CoachCardEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
