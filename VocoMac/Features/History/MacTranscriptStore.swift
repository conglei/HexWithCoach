//
//  MacTranscriptStore.swift
//  VocoMac
//
//  macOS bridge from the TCA history shell to the shared SwiftData store (MC-R3).
//
//  Background: the Mac app persisted history as flat JSON behind a TCA
//  `@Shared(.transcriptionHistory)` `FileStorageKey<TranscriptionHistory>`. MC-R2
//  re-founded a shared SwiftData schema on the Phase-3 lean row
//  (`TranscriptEntry` + faulted `TranscriptAnalysis` sidecar) plus a container
//  factory (`SyncStore.makeContainer()` in VocoEngine) that both apps compile
//  against and that syncs via CloudKit.
//
//  Rather than rewrite the TCA shell, this file keeps the `@Shared` projection as
//  an in-memory mirror and makes the SwiftData store the source of truth:
//
//    • At launch the app calls `MacTranscriptStore.shared.bootstrapAndHydrate`,
//      which stands up the shared container and loads the persisted
//      `TranscriptEntry` rows back into the `@Shared(.transcriptionHistory)`
//      projection so every existing read site (History list, Settings, the
//      menu-bar "Copy Last") keeps working unchanged.
//    • New dictations and deletes mirror into SwiftData through this store, so they
//      survive relaunch and sync via CloudKit (MC-R2).
//
//  Greenfield: there is NO JSON→SwiftData migration. This is the re-found line off
//  origin/main, which dropped MC-3's migration path — the store simply bootstraps
//  empty and hydrates from whatever the synced container already holds.
//
//  The store is inert until `bootstrapAndHydrate` runs, so unit tests that drive
//  the TCA features with an empty `Shared(.init())` never touch SwiftData.
//

import ComposableArchitecture
import Foundation
import SwiftData
import VocoCore

/// Owns the shared `ModelContainer` for the macOS app and bridges the TCA
/// `@Shared(.transcriptionHistory)` projection to the SwiftData source of truth.
@MainActor
final class MacTranscriptStore {
    static let shared = MacTranscriptStore()

    /// nil until `bootstrapAndHydrate` runs. While nil, all mirror writes are
    /// no-ops — this keeps unit tests (which never bootstrap) from touching disk.
    private var container: ModelContainer?

    private var context: ModelContext? { container?.mainContext }

    /// macOS Coach v2 state (MC-R4). Created at bootstrap alongside the container so
    /// Settings can bind to it and the capture hook can drive the objective lane.
    /// nil until `bootstrapAndHydrate` runs (e.g. unit tests never touch the coach).
    private(set) var coachPreferences: MacCoachPreferences?
    private(set) var coach: MacCoachService?

    /// The shared SwiftData container, once `bootstrapAndHydrate` has run. The
    /// companion window (MC-R0) injects this into its SwiftUI environment via
    /// `.modelContainer(_:)` so the History UI (MC-R8) can `@Query` the same store
    /// the TCA pipeline writes to. nil until bootstrap (e.g. unit tests).
    var modelContainer: ModelContainer? { container }

    private init() {}

    // MARK: - Bootstrap

    /// Build the shared container and hydrate the TCA
    /// `@Shared(.transcriptionHistory)` projection from the persisted rows. Safe to
    /// call once at launch. Returns the loaded history (newest-first).
    ///
    /// No migration: a freshly-installed store is simply empty; an existing synced
    /// store hydrates whatever CloudKit has already delivered.
    @discardableResult
    func bootstrapAndHydrate(
        into projection: Shared<TranscriptionHistory>
    ) -> TranscriptionHistory {
        let container = SyncStore.makeContainer()
        self.container = container
        let context = container.mainContext

        // Stand up the Coach v2 driver over the shared context (MC-R4). Preferences
        // mirror the iOS opt-in / BYOK / autoLLM / budget state via the same App
        // Group keys + Keychain account.
        let prefs = MacCoachPreferences()
        coachPreferences = prefs
        coach = MacCoachService(modelContext: context, preferences: prefs)

        // Hydrate the in-memory projection from the persisted store so every
        // existing read site keeps working against `@Shared(.transcriptionHistory)`.
        let history = TranscriptionHistory(history: loadTranscripts(from: context))
        projection.withLock { $0 = history }
        HexLog.history.notice("Hydrated \(history.history.count) Mac history entries from SwiftData")
        return history
    }

    // MARK: - Mirror writes (no-ops until bootstrapped)

    /// Upsert a freshly-captured dictation into the SwiftData store. Dedupes on
    /// `id`, so replaying a save is harmless. No-op until the store is bootstrapped.
    func insert(_ transcript: Transcript) {
        guard let context else { return }
        upsert(transcript, kind: .dictation, into: context)
        try? context.save()

        // Drive the Coach v2 objective lane at capture (MC-R4), then let it consider
        // an auto-batched LLM run. Idempotent + best-effort — coaching must never
        // block or fail a capture. Fire-and-forget so the save path returns promptly.
        let id = transcript.id
        if let coach {
            Task { @MainActor in
                let descriptor = FetchDescriptor<TranscriptEntry>(predicate: #Predicate { $0.id == id })
                guard let entry = try? context.fetch(descriptor).first else { return }
                await coach.autoAnalyzeOnCapture(entry)
            }
        }
    }

    /// Remove the entry with this id from the SwiftData store. No-op until
    /// bootstrapped; harmless when the id isn't present. The cascade delete rule on
    /// `analysis` removes the faulted sidecar too.
    func delete(id: UUID) {
        guard let context else { return }
        let descriptor = FetchDescriptor<TranscriptEntry>(
            predicate: #Predicate { $0.id == id }
        )
        guard let matches = try? context.fetch(descriptor) else { return }
        for entry in matches { context.delete(entry) }
        try? context.save()
    }

    /// Remove every transcript from the SwiftData store (mirrors "Delete All" and
    /// the "disable history" toggle). No-op until bootstrapped.
    func deleteAll() {
        guard let context else { return }
        guard let all = try? context.fetch(FetchDescriptor<TranscriptEntry>()) else { return }
        for entry in all { context.delete(entry) }
        try? context.save()
    }

    // MARK: - Reads

    /// All persisted transcripts mapped back to the TCA `Transcript` struct,
    /// newest-first to match the historical JSON ordering. Reads the lean row only;
    /// the heavy `analysis` sidecar is never faulted here.
    func loadTranscripts(from context: ModelContext) -> [Transcript] {
        let descriptor = FetchDescriptor<TranscriptEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.map(Self.makeTranscript(from:))
    }

    /// Windowed fetch (HS-2): the most-recent `limit` lean rows whose `date` falls in
    /// `[since, before)`, newest-first. The date-scope predicate + `fetchLimit` keep
    /// the History list bounded so it never scans the whole table, and it returns
    /// **lean rows** — the faulted `TranscriptAnalysis` sidecar is left untouched.
    /// MC-R8 builds the windowed History UI on top of this.
    ///
    /// - Parameters:
    ///   - since: inclusive lower bound on `date`; nil = no lower bound.
    ///   - before: exclusive upper bound on `date`; nil = up to now.
    ///   - limit: page size (HS-2 default ~50).
    func fetchWindow(
        since: Date? = nil,
        before: Date? = nil,
        limit: Int = 50
    ) -> [TranscriptEntry] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<TranscriptEntry>(
            predicate: Self.windowPredicate(since: since, before: before),
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Build the date-scope predicate for `fetchWindow`. Split out so the bounds
    /// logic is explicit and unit-testable shape-wise. Using `Date.distantPast` /
    /// `Date.distantFuture` for the open ends keeps the predicate a single
    /// comparable expression SwiftData can translate.
    static func windowPredicate(since: Date?, before: Date?) -> Predicate<TranscriptEntry> {
        let lower = since ?? .distantPast
        let upper = before ?? .distantFuture
        return #Predicate<TranscriptEntry> { entry in
            entry.date >= lower && entry.date < upper
        }
    }

    // MARK: - Upsert + mapping

    /// Insert or update the `TranscriptEntry` for this transcript's id. Heavy
    /// artifacts (word timings / pronunciation result) are not written here — a
    /// captured dictation has none yet; the coach lane (MC-R4) attaches them later
    /// through the `TranscriptEntry` accessors, which create the faulted sidecar
    /// on demand.
    private func upsert(_ transcript: Transcript, kind: TranscriptKind, into context: ModelContext) {
        let id = transcript.id
        let descriptor = FetchDescriptor<TranscriptEntry>(
            predicate: #Predicate { $0.id == id }
        )
        let audioFilename = transcript.audioPath.lastPathComponent.isEmpty
            ? nil
            : transcript.audioPath.lastPathComponent

        if let existing = try? context.fetch(descriptor), let entry = existing.first {
            entry.text = transcript.text
            entry.date = transcript.timestamp
            entry.kindRaw = kind.rawValue
            entry.sourceAppName = transcript.sourceAppName
            entry.sourceAppBundleID = transcript.sourceAppBundleID
            entry.audioFilename = audioFilename
            entry.duration = transcript.duration
        } else {
            let entry = TranscriptEntry(
                text: transcript.text,
                date: transcript.timestamp,
                kind: kind,
                sourceAppName: transcript.sourceAppName,
                sourceAppBundleID: transcript.sourceAppBundleID,
                audioFilename: audioFilename,
                duration: transcript.duration
            )
            entry.id = id
            context.insert(entry)
        }
    }

    // MARK: - Static helpers (pure, testable)

    /// Map a persisted `TranscriptEntry` back to the TCA `Transcript` struct. Audio
    /// is referenced by filename inside the Mac `Recordings/` dir; resolve it to an
    /// absolute path for playback (a placeholder path when not recoverable). Reads
    /// only lean-row fields — never touches the `analysis` sidecar.
    static func makeTranscript(from entry: TranscriptEntry) -> Transcript {
        Transcript(
            id: entry.id,
            timestamp: entry.date,
            text: entry.text,
            audioPath: recordingsURL(for: entry.audioFilename),
            duration: entry.duration,
            sourceAppBundleID: entry.sourceAppBundleID,
            sourceAppName: entry.sourceAppName
        )
    }

    /// The on-disk URL for a stored Mac recording filename, in the same
    /// `Recordings/` dir `TranscriptPersistenceClient` writes to. Returns a
    /// placeholder file URL when there's no filename / the app-support dir is
    /// unavailable, so callers always have a non-optional `audioPath`.
    static func recordingsURL(for filename: String?) -> URL {
        guard let filename, !filename.isEmpty else {
            return URL(fileURLWithPath: "/dev/null")
        }
        guard let support = try? URL.hexApplicationSupport else {
            return URL(fileURLWithPath: filename)
        }
        return support
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
