//
//  PracticeStore.swift
//  Voco
//
//  Practice items (PR-1) — target text the learner practices via the shadowing
//  loop (TTS → speak → ASR/GOP score). Coach-card, phrasebook, and pasted/typed
//  targets are NOT captures: they're modeled as their *own* type, deliberately
//  separate from `TranscriptEntry`, so they can never surface in History queries.
//
//  CloudKit-backed SwiftData requires every attribute to have a default, so all
//  stored properties are defaulted/optional and relationships are CloudKit-safe.
//

import Foundation
import SwiftData

/// A unit of practice: target text (split into speakable `segments`) plus its
/// provenance and the learner's recorded `attempts`. Persisted in the shared
/// `ModelContainer` (synced via CloudKit) but never queried by History — History
/// only fetches `TranscriptEntry`, a different type entirely.
@Model
final class PracticeItem {
    // CloudKit-backed SwiftData requires every attribute to have a default.
    var id: UUID = UUID()
    /// Optional display title (e.g. the coach card's title); nil for raw paste.
    var title: String?
    /// The full target text the learner is practicing.
    var sourceText: String = ""
    /// Speakable sentences derived from `sourceText`. SwiftData persists `[String]`.
    var segments: [String] = []
    /// Backing store for `origin`; see `Origin`. Stored as a String for CloudKit.
    var originRaw: String = Origin.pasted.rawValue
    /// Links back to the coach card / insight or phrasebook entry this item came
    /// from. nil when the target was pasted/typed (no source to link to).
    var sourceID: UUID?
    var createdAt: Date = Date()

    /// The learner's recorded attempts at this item. Cascade-deleted with the item
    /// so deleting a practice item also removes its attempt history (DM-1 style).
    @Relationship(deleteRule: .cascade, inverse: \PracticeAttempt.item)
    var attempts: [PracticeAttempt] = []

    /// Where this practice target came from. Drives provenance + (later) the paste
    /// vs. coach-card vs. phrasebook entry points. Decoded from `originRaw`.
    var origin: Origin {
        get { Origin(rawValue: originRaw) ?? .pasted }
        set { originRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String? = nil,
        sourceText: String = "",
        segments: [String] = [],
        origin: Origin = .pasted,
        sourceID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sourceText = sourceText
        self.segments = segments
        self.originRaw = origin.rawValue
        self.sourceID = sourceID
        self.createdAt = createdAt
    }
}

extension PracticeItem {
    /// Provenance of a practice item. Kept out of the `@Model` body so the
    /// SwiftData schema macro only sees stored properties.
    enum Origin: String, Codable, Sendable {
        case pasted        // raw text the user pasted or typed (no source link)
        case coachInsight  // generated from a coach card / insight (`sourceID`)
        case phrasebook    // a saved phrasebook entry (`sourceID`)
    }
}

/// One recorded attempt at a `PracticeItem`. Reuses the shadowing scoring shape:
/// `ShadowingModel` produces a `score: Double` per spoken segment (the ASR match)
/// plus an optional GOP delta versus the previous attempt. We persist the
/// per-segment scores and the GOP delta so progress over time becomes a query.
///
/// All fields are defaulted/optional so the model is CloudKit-compatible.
@Model
final class PracticeAttempt {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Per-segment ASR match scores (one `Double` per `PracticeItem.segments`
    /// entry), mirroring `ShadowingModel.score`. SwiftData persists `[Double]`.
    var perSegmentScores: [Double] = []
    /// Goodness-of-pronunciation delta vs. the previous attempt (the closed-loop
    /// improvement from `ShadowingGOP.Comparison`). nil when no comparison existed
    /// (first attempt, or no pronunciation model).
    var gopDelta: Double?
    /// Inverse of `PracticeItem.attempts`. Defaulted for CloudKit.
    var item: PracticeItem?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        perSegmentScores: [Double] = [],
        gopDelta: Double? = nil,
        item: PracticeItem? = nil
    ) {
        self.id = id
        self.date = date
        self.perSegmentScores = perSegmentScores
        self.gopDelta = gopDelta
        self.item = item
    }
}

/// Minimal creation helpers for `PracticeItem`. Kept intentionally small — the
/// model + container registration is the PR-1 deliverable; the UI (PR-2) and the
/// paste flow (PR-3) build on top of this.
enum PracticeStore {
    /// Build a practice item from raw pasted/typed text.
    static func pasted(_ text: String, segments: [String], title: String? = nil) -> PracticeItem {
        PracticeItem(title: title, sourceText: text, segments: segments, origin: .pasted)
    }

    /// Build a practice item sourced from a coach card / insight.
    static func coachInsight(_ text: String, segments: [String], sourceID: UUID, title: String? = nil) -> PracticeItem {
        PracticeItem(title: title, sourceText: text, segments: segments, origin: .coachInsight, sourceID: sourceID)
    }

    /// Build a practice item sourced from a phrasebook entry.
    static func phrasebook(_ text: String, segments: [String], sourceID: UUID, title: String? = nil) -> PracticeItem {
        PracticeItem(title: title, sourceText: text, segments: segments, origin: .phrasebook, sourceID: sourceID)
    }
}
