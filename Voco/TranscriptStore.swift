//
//  TranscriptStore.swift
//  HexIOS
//
//  Persistent, iCloud-synced transcript history (P4-2). SwiftData persists
//  locally (history survives relaunch) and, with the CloudKit container, syncs
//  across the user's devices automatically.
//

import AVFoundation
import Foundation
import VocoCore
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
    // History is sorted by date and segmented by kind, so index both (DM-1).
    // `#Index` is iOS 18+; the app floor is 17.6, so gate it.
    @available(iOS 18, *)
    #Index<TranscriptEntry>([\.date], [\.kindRaw])

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
    /// When the **LLM lane** (paid, BYOK) analyzed this transcript. nil = still in
    /// the LLM backlog (RC-2). Named for the LLM lane specifically; the free
    /// objective lane tracks its own idempotency via `objectiveAnalyzedAt`.
    var coachAnalyzedAt: Date?
    /// When the free **objective lane** (GOP + fluency) last ran for this note
    /// (CI-7). nil = it hasn't run yet, so the note is eligible to run
    /// automatically at capture. Distinct from `coachAnalyzedAt` because the lanes
    /// run independently: the objective lane is always-on + keyless, the LLM lane
    /// is gated by key + toggle + budget. Defaulted for CloudKit.
    var objectiveAnalyzedAt: Date?
    /// Compact pronunciation summary (JSON-encoded `PronunciationSignals`, ~1 KB)
    /// kept *on the row* so corpus analytics / the History list read it without
    /// faulting the heavy sidecar (DM-1). Refreshed whenever `pronunciationResult`
    /// is set; nil when no result was captured. Stored as JSON so CloudKit can sync.
    var pronunciationSummaryJSON: String?
    /// Heavy per-note artifacts (word timings, full pronunciation result), split
    /// into a lazily-faulted sidecar so fetching the row stays cheap (DM-1).
    /// Cascade-deleted with the entry.
    @Relationship(deleteRule: .cascade, inverse: \TranscriptAnalysis.entry)
    var analysis: TranscriptAnalysis?

    var kind: TranscriptKind { TranscriptKind(rawValue: kindRaw) ?? .note }

    /// Decoded word timings, or nil when none were captured. Heavy → sidecar,
    /// faulted only on access; create-on-write via `ensureAnalysis()`.
    var wordTimings: [WordTiming]? {
        get { analysis?.wordTimings }
        set { ensureAnalysis().wordTimings = newValue }
    }

    /// Decoded per-note pronunciation result, or nil when none was captured. Heavy
    /// → sidecar (faulted lazily); on set, also refresh the compact on-row summary.
    var pronunciationResult: PronunciationResult? {
        get { analysis?.pronunciationResult }
        set {
            ensureAnalysis().pronunciationResult = newValue
            guard let newValue, !newValue.words.isEmpty,
                  let data = try? JSONEncoder().encode(PronunciationSignals(result: newValue)) else {
                pronunciationSummaryJSON = nil
                return
            }
            pronunciationSummaryJSON = String(data: data, encoding: .utf8)
        }
    }

    /// Compact pronunciation summary (CI-3), decoded from the on-row JSON. Cheap:
    /// reads `pronunciationSummaryJSON` directly and never faults the sidecar (DM-1).
    var pronunciationSignals: PronunciationSignals? {
        guard let json = pronunciationSummaryJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PronunciationSignals.self, from: data)
    }

    /// Return the heavy sidecar, creating and linking it on first write.
    private func ensureAnalysis() -> TranscriptAnalysis {
        if let analysis { return analysis }
        let created = TranscriptAnalysis()
        created.entry = self
        analysis = created
        return created
    }

    init(text: String, date: Date, kind: TranscriptKind, sourceAppName: String? = nil, audioFilename: String? = nil) {
        self.text = text
        self.date = date
        self.kindRaw = kind.rawValue
        self.sourceAppName = sourceAppName
        self.audioFilename = audioFilename
    }
}

/// Heavy per-note artifacts that the History list and corpus scans never need
/// (DM-1). Split off `TranscriptEntry` into this sidecar so a to-one relationship
/// faults it lazily — fetching the lean row doesn't load these bulky blobs.
@Model
final class TranscriptAnalysis {
    // CloudKit-backed SwiftData requires every attribute to have a default.
    var id: UUID = UUID()
    /// Word-level timings (JSON-encoded `[WordTiming]`) for audio↔text sync in the
    /// detail view. Populated for Parakeet notes; nil when the model didn't expose
    /// timings (older notes, Whisper/Qwen). Stored as JSON so CloudKit can sync it.
    var wordTimingsJSON: String?
    /// Per-note pronunciation result (JSON-encoded `PronunciationResult`) from the
    /// on-device GOP analyzer (CI-3). Populated when the phoneme model is present;
    /// nil otherwise (keyless-no-model state, or analysis not yet run). Stored as
    /// JSON, exactly like `wordTimingsJSON`, so CloudKit can sync it.
    var pronunciationJSON: String?
    /// Inverse of `TranscriptEntry.analysis`. Defaulted for CloudKit.
    var entry: TranscriptEntry?

    /// Decoded word timings, or nil when none were captured.
    var wordTimings: [WordTiming]? {
        get {
            guard let json = wordTimingsJSON, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([WordTiming].self, from: data)
        }
        set {
            guard let newValue, !newValue.isEmpty, let data = try? JSONEncoder().encode(newValue) else {
                wordTimingsJSON = nil
                return
            }
            wordTimingsJSON = String(data: data, encoding: .utf8)
        }
    }

    /// Decoded per-note pronunciation result, or nil when none was captured.
    var pronunciationResult: PronunciationResult? {
        get {
            guard let json = pronunciationJSON, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(PronunciationResult.self, from: data)
        }
        set {
            guard let newValue, !newValue.words.isEmpty, let data = try? JSONEncoder().encode(newValue) else {
                pronunciationJSON = nil
                return
            }
            pronunciationJSON = String(data: data, encoding: .utf8)
        }
    }

    init() {}
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
    var context: String?
    var practiceText: String?
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
        context = card.context
        practiceText = card.practiceText
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

    // MARK: - In-progress note spans (pause/resume)

    /// Sub-directory holding finalized spans of an in-progress note. Spans are
    /// moved here the moment the user pauses, so a crash/kill before "Done" can't
    /// lose already-recorded audio. They're concatenated and cleaned up on finish.
    @MainActor
    private static var draftsDirectory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HexAppGroup.identifier)
        else { return nil }
        let dir = container.appendingPathComponent("Drafts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Draft spans left on disk from an interrupted note (app killed while paused,
    /// or a transcription that failed before saving), sorted oldest-first so they
    /// concatenate in recording order. Empty after a clean finish/cancel.
    @MainActor
    static func orphanedDraftSegments() -> [URL] {
        guard let dir = draftsDirectory else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da < db
            }
    }

    /// Move a finalized span from temp into the crash-safe Drafts dir; returns its
    /// URL (or nil, having cleaned up, if it couldn't be retained).
    @MainActor
    static func persistDraftSegment(_ tempURL: URL) -> URL? {
        guard let dir = draftsDirectory else { try? FileManager.default.removeItem(at: tempURL); return nil }
        let dest = dir.appendingPathComponent("\(UUID().uuidString).wav")
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }

    /// Concatenate same-format WAV spans (16 kHz mono PCM) into one temp clip for
    /// transcription + playback. All spans come from `AudioRecorder`, so they share
    /// a format; the output is written with that same format.
    @MainActor
    static func concatenate(_ urls: [URL]) throws -> URL {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hex-note-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(forWriting: outURL, settings: settings)
        for url in urls {
            let input = try AVAudioFile(forReading: url)
            let frames = AVAudioFrameCount(input.length)
            guard frames > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: frames)
            else { continue }
            try input.read(into: buffer)
            try output.write(from: buffer)
        }
        return outURL
    }
}

enum TranscriptStore {
    /// Build the model container. Prefers the CloudKit-synced store; falls back
    /// to a local-only store if CloudKit is unavailable (e.g. no iCloud account).
    @MainActor
    static func makeContainer() -> ModelContainer {
        if SyncPreferences.iCloudEnabled,
           let cloud = try? ModelContainer(
               for: TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
               configurations: ModelConfiguration(cloudKitDatabase: .automatic)
           ) {
            return cloud
        }
        if let local = try? ModelContainer(
            for: TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
            configurations: ModelConfiguration(cloudKitDatabase: .none)
        ) {
            return local
        }
        // In-memory last resort so the app still runs.
        return try! ModelContainer(
            for: TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// One-time repair: when `TranscriptEntry.id` was added, SwiftData's
    /// lightweight migration filled every pre-existing row with the *same*
    /// default UUID, which collides in `ForEach` and breaks card↔transcript
    /// links. Reassign duplicates a fresh id. Cheap, idempotent.
    @MainActor
    static func ensureUniqueIDs(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<TranscriptEntry>()) else { return }
        var seen = Set<UUID>()
        var changed = false
        for entry in all {
            if seen.contains(entry.id) {
                entry.id = UUID()
                changed = true
            }
            seen.insert(entry.id)
        }
        if changed { try? context.save() }
    }
}
