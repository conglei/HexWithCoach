//
//  TranscriptDeletion.swift
//  Voco
//
//  HS-3: cascade-delete a note/dictation and every satellite it spawned, so no
//  orphaned audio file, ghost Review card, observation row, or growth snapshot
//  survives. Deletion is otherwise unsupported anywhere in the app; this is the
//  one place that knows the full fan-out, so swipe-to-delete and bulk delete both
//  route through it.
//
//  Fan-out per deleted entry (data-model §Deletion):
//    1. `modelContext.delete(entry)` — its `TranscriptAnalysis` sidecar follows via
//       the `.cascade` relationship rule (DM-1).
//    2. The audio file in the App Group `Audio` dir (`entry.audioFilename`).
//    3. `CoachCardEntity` rows where `transcriptID == entry.id` (Review feed).
//    4. `CoachObservation` rows where `noteID == entry.id` (DM-2 log).
//    5. The `CoachSnapshot` for the note in the file-backed growth log (CI-13).
//

import Foundation
import VocoCore
import SwiftData

enum TranscriptDeletion {
    /// Cascade-delete one entry and all of its satellites, then save. Best-effort
    /// on the file-backed pieces (audio, snapshot) — a failure there must not block
    /// removing the row. The caller owns calling `save` semantics; we save once at
    /// the end so a bulk delete can batch many entries before its own save instead.
    ///
    /// `save` defaults true (single-row swipe). Bulk deletes pass `save: false` and
    /// save once after the loop.
    @MainActor
    static func delete(_ entry: TranscriptEntry, in context: ModelContext, save: Bool = true) {
        let id = entry.id
        let audioFilename = entry.audioFilename

        // 1. The row (+ its cascade-linked TranscriptAnalysis sidecar).
        context.delete(entry)

        // 2. Audio file — portable filename in the App Group Audio dir.
        removeAudio(audioFilename)

        // 3. Review-feed cards keyed to this transcript.
        if let cards = try? context.fetch(
            FetchDescriptor<CoachCardEntity>(predicate: #Predicate { $0.transcriptID == id })
        ) {
            for card in cards { context.delete(card) }
        }

        // 4. Observation-log rows for this note (DM-2).
        deleteObservations(noteID: id, in: context)

        // 5. Growth-history snapshot for this note (CI-13).
        try? snapshotStore.remove(noteID: id)

        if save { try? context.save() }
    }

    /// Cascade-delete several entries, saving once at the end so SwiftData batches
    /// the writes. Used by Select-mode bulk delete and "clear all".
    @MainActor
    static func delete(_ entries: [TranscriptEntry], in context: ModelContext) {
        guard !entries.isEmpty else { return }
        for entry in entries { delete(entry, in: context, save: false) }
        try? context.save()
    }

    /// Delete every `CoachObservation` for a note. Shared with `CoachService`'s
    /// re-analyze path (DM-2 dedup): re-analyzing must clear a note's old
    /// observations before re-recording, or frequency-over-time queries double-count.
    @MainActor
    static func deleteObservations(noteID: UUID, in context: ModelContext) {
        guard let rows = try? context.fetch(
            FetchDescriptor<CoachObservation>(predicate: #Predicate { $0.noteID == noteID })
        ) else { return }
        for row in rows { context.delete(row) }
    }

    // MARK: - File-backed satellites

    @MainActor
    private static func removeAudio(_ filename: String?) {
        guard let url = AudioStore.url(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The growth-history snapshot log. Resolved through the single source of truth
    /// (`CoachPaths`) so the deletion path here targets exactly the file
    /// `CoachService` writes — including on the no-entitlement / nil-container branch.
    @MainActor
    private static var snapshotStore: CoachSnapshotStore {
        CoachSnapshotStore(url: CoachPaths.snapshotsURL())
    }
}
