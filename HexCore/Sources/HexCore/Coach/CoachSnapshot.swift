//
//  CoachSnapshot.swift
//  HexCore
//
//  The durable record behind "how you grow over time". One small, append-only
//  snapshot of a note's *objective* signals (fluency + pronunciation GOP) is
//  written by the objective lane when a note is analyzed — keyless, for every
//  user, so a real growth history exists from day one without an API key.
//
//  Why persist instead of recomputing from the corpus (as `ProgressSummary`
//  does for pronunciation)? GOP is derived from the audio file. If audio is ever
//  pruned for storage, that history is gone forever — the snapshot captures it at
//  analysis time so the curve survives. Fluency metrics are stable per-note
//  functions of stored text/timings, so a launch backfill can seed history from
//  existing notes.
//
//  Scope is deliberately *per-note objective metrics only*. Mastery milestones
//  ("patterns mastered over time") come from `RecurringPattern.firstSeen/recency`
//  in the profile, which carry real dates — not from corpus-wide counts that
//  would look identical on every backfilled snapshot. Each growth source stays
//  honest about what it actually measures.
//

import Foundation

// MARK: - Snapshot

/// One note's objective signals, frozen at analysis time. `date` is the note's
/// *capture* date (not the analysis date) so trends and weekly buckets line up
/// with when the speaking actually happened — and so backfilled snapshots land
/// on their real days.
public struct CoachSnapshot: Codable, Sendable, Equatable, Identifiable {
    /// The transcript this snapshot belongs to. Stable identity → upsert key.
    public var noteID: UUID
    /// The note's capture date.
    public var date: Date
    /// Utterance duration in seconds (real audio duration when available).
    public var durationSec: Double
    /// Whitespace-tokenized word count.
    public var wordCount: Int

    /// Filler tokens/phrases per minute (um/uh/like/…).
    public var fillersPerMinute: Double
    /// Words per minute.
    public var wordsPerMinute: Double
    /// Fraction (0…1) of inter-word gaps longer than ~1s. Zero unless timings present.
    public var longPauseRate: Double
    /// Immediate repeats + dash self-corrections.
    public var restartCount: Int
    /// Whether pause-derived fields were actually measured (word timings present).
    public var hasPauseStats: Bool

    /// Mean goodness-of-pronunciation over this note's phonemes (≤ 0; closer to 0
    /// is better). `nil` when no pronunciation result was available (no phoneme
    /// model, or out-of-dictionary). Kept optional so GOP trends never plot a
    /// placeholder zero as if it were a perfect score.
    public var overallGOP: Double?

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        date: Date,
        durationSec: Double,
        wordCount: Int,
        fillersPerMinute: Double,
        wordsPerMinute: Double,
        longPauseRate: Double,
        restartCount: Int,
        hasPauseStats: Bool,
        overallGOP: Double?
    ) {
        self.noteID = noteID
        self.date = date
        self.durationSec = durationSec
        self.wordCount = wordCount
        self.fillersPerMinute = fillersPerMinute
        self.wordsPerMinute = wordsPerMinute
        self.longPauseRate = longPauseRate
        self.restartCount = restartCount
        self.hasPauseStats = hasPauseStats
        self.overallGOP = overallGOP
    }

    /// Build a snapshot from the objective signals already computed for a note.
    /// `pronunciation` is optional — absent when the phoneme model isn't present.
    /// A GOP of exactly `0` means "no measurement" (the signals' empty sentinel),
    /// so it's stored as `nil` rather than a misleading perfect score.
    public init(
        noteID: UUID,
        date: Date,
        fluency: FluencySignals,
        pronunciation: PronunciationSignals?
    ) {
        let gop = pronunciation?.overallGOP
        self.init(
            noteID: noteID,
            date: date,
            durationSec: fluency.durationSec,
            wordCount: fluency.wordCount,
            fillersPerMinute: fluency.fillersPerMinute,
            wordsPerMinute: fluency.wordsPerMinute,
            longPauseRate: fluency.longPauseRate,
            restartCount: fluency.restartCount,
            hasPauseStats: fluency.hasPauseStats,
            overallGOP: (gop != nil && gop! < 0) ? gop : nil
        )
    }
}

// MARK: - Weekly rollup

/// One week's aggregate over the notes captured in it. Means are taken only over
/// notes that actually carried the signal (GOP over notes with a result), so a
/// silent note never drags an average toward zero.
public struct CoachWeeklyRollup: Sendable, Equatable, Identifiable {
    /// Start-of-week (per the calendar used to build it).
    public var weekStart: Date
    public var noteCount: Int
    public var totalDurationSec: Double
    public var meanFillersPerMinute: Double
    public var meanWordsPerMinute: Double
    public var meanLongPauseRate: Double
    /// Mean GOP over notes in this week that had a result; `nil` if none did.
    public var meanGOP: Double?

    public var id: Date { weekStart }

    public init(
        weekStart: Date,
        noteCount: Int,
        totalDurationSec: Double,
        meanFillersPerMinute: Double,
        meanWordsPerMinute: Double,
        meanLongPauseRate: Double,
        meanGOP: Double?
    ) {
        self.weekStart = weekStart
        self.noteCount = noteCount
        self.totalDurationSec = totalDurationSec
        self.meanFillersPerMinute = meanFillersPerMinute
        self.meanWordsPerMinute = meanWordsPerMinute
        self.meanLongPauseRate = meanLongPauseRate
        self.meanGOP = meanGOP
    }
}

// MARK: - Log

/// The append-only history of snapshots, kept sorted by date ascending. Upsert is
/// keyed by `noteID` so a manual re-analyze refreshes a note's snapshot in place
/// rather than duplicating it. Pure value type — the store owns persistence.
public struct CoachSnapshotLog: Codable, Sendable, Equatable {
    public private(set) var snapshots: [CoachSnapshot]

    public init(_ snapshots: [CoachSnapshot] = []) {
        self.snapshots = snapshots.sorted { $0.date < $1.date }
    }

    public var isEmpty: Bool { snapshots.isEmpty }
    public var count: Int { snapshots.count }

    /// Insert or replace the snapshot for a note, keeping the log date-sorted.
    public mutating func upsert(_ snapshot: CoachSnapshot) {
        snapshots.removeAll { $0.noteID == snapshot.noteID }
        let idx = snapshots.firstIndex { $0.date > snapshot.date } ?? snapshots.endIndex
        snapshots.insert(snapshot, at: idx)
    }

    /// Snapshots captured on/after `date` (the "this week"/"this month" slice).
    public func since(_ date: Date) -> [CoachSnapshot] {
        snapshots.filter { $0.date >= date }
    }

    /// Roll the log up into per-week aggregates, oldest week first. `calendar`
    /// decides week boundaries — pass a fixed-timezone calendar for determinism.
    public func weekly(calendar: Calendar = .current) -> [CoachWeeklyRollup] {
        guard !snapshots.isEmpty else { return [] }

        let grouped = Dictionary(grouping: snapshots) { snap -> Date in
            calendar.dateInterval(of: .weekOfYear, for: snap.date)?.start ?? snap.date
        }

        return grouped.keys.sorted().map { weekStart in
            let week = grouped[weekStart] ?? []
            let gops = week.compactMap(\.overallGOP)
            return CoachWeeklyRollup(
                weekStart: weekStart,
                noteCount: week.count,
                totalDurationSec: week.reduce(0) { $0 + $1.durationSec },
                meanFillersPerMinute: Self.mean(week.map(\.fillersPerMinute)),
                meanWordsPerMinute: Self.mean(week.map(\.wordsPerMinute)),
                meanLongPauseRate: Self.mean(week.map(\.longPauseRate)),
                meanGOP: gops.isEmpty ? nil : Self.mean(gops)
            )
        }
    }

    private static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }
}

// MARK: - Store

/// File-backed persistence for the snapshot log, mirroring `LearnerProfileStore`:
/// a single JSON document in the App Group's `Coach` directory, written
/// atomically. Cross-process safe enough for our single-writer (the app) usage.
public struct CoachSnapshotStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func load() -> CoachSnapshotLog {
        guard let data = try? Data(contentsOf: url),
              let log = try? Self.decoder.decode(CoachSnapshotLog.self, from: data)
        else { return CoachSnapshotLog() }
        return log
    }

    public func save(_ log: CoachSnapshotLog) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(log)
        try data.write(to: url, options: .atomic)
    }

    /// Load, upsert one snapshot, and persist. The single entry point the capture
    /// path calls per analyzed note.
    public func record(_ snapshot: CoachSnapshot) throws {
        var log = load()
        log.upsert(snapshot)
        try save(log)
    }
}
