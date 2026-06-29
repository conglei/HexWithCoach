//
//  MacTranscriptDeletion.swift
//  VocoMac
//
//  MC-R8: cascade-delete a History entry and every satellite it spawned, so no
//  orphaned audio file, ghost Review card, observation row, or growth snapshot
//  survives. This is the macOS counterpart to iOS `TranscriptDeletion` (HS-3):
//  same fan-out, but the audio file lives in the Mac `Recordings/` dir (resolved
//  via `MacTranscriptStore.recordingsURL`) rather than the App Group `Audio` dir,
//  and the growth-snapshot store is resolved the same way `MacCoachService` does
//  (App Group `Coach/snapshots.json`, temp-dir fallback).
//
//  Fan-out per deleted entry:
//    1. `modelContext.delete(entry)` — its `TranscriptAnalysis` sidecar follows via
//       the `.cascade` relationship rule (DM-1). We never fault `analysis` here.
//    2. The audio file in the Mac `Recordings/` dir (`entry.audioFilename`).
//    3. `CoachCardEntity` rows where `transcriptID == entry.id` (Review feed).
//    4. `CoachObservation` rows where `noteID == entry.id` (DM-2 log).
//    5. The `CoachSnapshot` for the note in the file-backed growth log (CI-13).
//

import Foundation
import SwiftData
import VocoCore

enum MacTranscriptDeletion {
    /// Cascade-delete one entry and all of its satellites, then save. Best-effort
    /// on the file-backed pieces (audio, snapshot) — a failure there must not block
    /// removing the row. Saves once at the end unless `save: false` (bulk path).
    @MainActor
    static func delete(_ entry: TranscriptEntry, in context: ModelContext, save: Bool = true) {
        // Capture the lean-row identity fields up front; never fault `analysis`.
        let id = entry.id
        let audioFilename = entry.audioFilename

        // 1. The row (+ its cascade-linked TranscriptAnalysis sidecar).
        context.delete(entry)

        // 2. Audio file — portable filename in the Mac Recordings dir.
        removeAudio(audioFilename)

        // 3. Review-feed cards keyed to this transcript.
        if let cards = try? context.fetch(
            FetchDescriptor<CoachCardEntity>(predicate: #Predicate { $0.transcriptID == id })
        ) {
            for card in cards { context.delete(card) }
        }

        // 4. Observation-log rows for this note (DM-2).
        if let rows = try? context.fetch(
            FetchDescriptor<CoachObservation>(predicate: #Predicate { $0.noteID == id })
        ) {
            for row in rows { context.delete(row) }
        }

        // 5. Growth-history snapshot for this note (CI-13).
        try? snapshotStore.remove(noteID: id)

        if save { try? context.save() }
    }

    /// Cascade-delete several entries, saving once at the end so SwiftData batches
    /// the writes. Used by Select-mode bulk delete.
    @MainActor
    static func delete(_ entries: [TranscriptEntry], in context: ModelContext) {
        guard !entries.isEmpty else { return }
        for entry in entries { delete(entry, in: context, save: false) }
        try? context.save()
    }

    // MARK: - File-backed satellites

    /// Remove the on-disk recording for a deleted entry. Resolves through the same
    /// `Recordings/` dir the Mac capture path writes to (`MacTranscriptStore`),
    /// so deletes and reads agree on the filename → URL mapping.
    @MainActor
    private static func removeAudio(_ filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        let url = MacTranscriptStore.recordingsURL(for: filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// The growth-history snapshot log, resolved the same way `MacCoachService`
    /// does (App Group `Coach/snapshots.json`, temp dir fallback) so both read and
    /// write the same file.
    private static var snapshotStore: CoachSnapshotStore {
        let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HexAppGroup.identifier)?
            .appendingPathComponent("Coach", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
        return CoachSnapshotStore(url: dir.appendingPathComponent("snapshots.json"))
    }
}
