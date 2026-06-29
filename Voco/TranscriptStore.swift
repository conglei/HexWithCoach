//
//  TranscriptStore.swift
//  HexIOS
//
//  Persistent, iCloud-synced transcript history (P4-2). The SwiftData `@Model`
//  schema (TranscriptEntry, TranscriptAnalysis, CoachCardEntity, CoachObservation,
//  PracticeItem/Attempt), the `TranscriptKind` enum, the `SyncPreferences`, and the
//  CloudKit-capable `ModelContainer` factory now live in the shared VocoEngine
//  layer — `VocoEngine/SyncModels.swift` and `VocoEngine/SyncStore.swift` — so both
//  the iOS (`Voco`) and macOS (`VocoMac`) targets compile the same synced schema
//  (MC-R2). This file keeps the iOS-specific store logic that consumes them:
//  persistent audio storage and the one-time id-uniqueness repair.
//

import AVFoundation
import Foundation
import VocoCore
import SwiftData

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
    /// Build the model container. Delegates to the shared `SyncStore` factory
    /// (VocoEngine), which both app targets use so they build one synced schema.
    @MainActor
    static func makeContainer() -> ModelContainer {
        SyncStore.makeContainer()
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
