//
//  SyncModels.swift
//  VocoEngine (shared: macOS VocoMac + iOS Voco)
//
//  The SwiftData Phase-3 schema, shared across both app targets (MC-R2). These
//  `@Model` types persist locally and sync via CloudKit. They depend only on
//  VocoCore + Foundation/AVFoundation/SwiftData (no UIKit/AppKit), so they
//  compile into both the iOS (`Voco`) and macOS (`VocoMac`) app modules.
//
//  Moved verbatim from `Voco/TranscriptStore.swift`, `Voco/PracticeStore.swift`,
//  and `Voco/DictationModel.swift` (TranscriptKind) so a single synced schema
//  backs both apps. iOS behavior is unchanged; macOS now compiles against it.
//

import AVFoundation
import Foundation
import SwiftData
import VocoCore

/// What produced a transcript — the coaching corpus distinguishes guided in-app
/// notes from natural cross-app dictation (Review/Coach design §13, RC-0).
enum TranscriptKind: String, Codable, Equatable {
    case dictation  // cross-app / keyboard Flow Session
    case note       // in-app capture from the app

    var label: String {
        switch self {
        case .dictation: "Dictation"
        case .note: "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation: "keyboard"
        case .note: "note.text"
        }
    }
}

@Model
final class TranscriptEntry {
    // History is sorted by date and segmented by kind, so index both (DM-1).
    // `#Index` needs iOS 18 / macOS 15; the iOS floor is 17.6, so gate it. The
    // macOS gate is required now that this model compiles into VocoMac too (MC-R2).
    @available(iOS 18, macOS 15, *)
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
    /// Bundle identifier of the host app for a cross-app dictation, when known.
    /// Populated by the macOS app (which can read the frontmost app); used to
    /// resolve an app icon/name in History. Additive + defaulted for CloudKit (MC-R3).
    var sourceAppBundleID: String?
    /// Length of the captured audio in seconds. Carried from the macOS `Transcript`
    /// so History can show a duration without faulting the heavy sidecar. Additive +
    /// defaulted for CloudKit (MC-R3); 0 when unknown.
    var duration: TimeInterval = 0
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

    init(
        text: String,
        date: Date,
        kind: TranscriptKind,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        audioFilename: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.text = text
        self.date = date
        self.kindRaw = kind.rawValue
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.audioFilename = audioFilename
        self.duration = duration
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
/// `CoachCard` (VocoCore) so the feed can `@Query` it and it syncs via CloudKit.
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

/// Append-only, dated record of a single coaching finding (DM-2). Every insight the
/// LLM lane verifies and every objective per-word GOP finding is persisted here
/// *before* curation, so cross-note coaching (frequency over time, regression,
/// evidence trails, per-word GOP trends) becomes a query rather than something
/// reconstructed from transient insights. Curation and the LearnerProfile are
/// unchanged — this only ADDS persistence.
///
/// All fields are defaulted/optional so the model is CloudKit-compatible.
@Model
final class CoachObservation {
    var id: UUID = UUID()
    /// The note this finding came from.
    var noteID: UUID = UUID()
    /// The note's capture date — trends bucket by speaking day, not analysis time.
    var date: Date = Date()
    var lensRaw: String = ""
    var originRaw: String = ""
    /// The canonical pattern slug (LLM lane) — stable across runs for dedupe.
    var patternKey: String?
    /// The word this finding is about (objective per-word GOP lane).
    var word: String?
    /// Goodness-of-pronunciation score for `word` (≤ 0; closer to 0 = better).
    var gop: Double?
    var severity: Int = 0
    /// The learner's exact words being flagged (LLM lane). Sensitive — never log plainly.
    var span: String?

    init(
        id: UUID = UUID(),
        noteID: UUID = UUID(),
        date: Date = Date(),
        lensRaw: String = "",
        originRaw: String = "",
        patternKey: String? = nil,
        word: String? = nil,
        gop: Double? = nil,
        severity: Int = 0,
        span: String? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.date = date
        self.lensRaw = lensRaw
        self.originRaw = originRaw
        self.patternKey = patternKey
        self.word = word
        self.gop = gop
        self.severity = severity
        self.span = span
    }
}

extension CoachObservation {
    /// Which lane authored this observation. Kept out of the `@Model` body so the
    /// SwiftData schema macro only sees stored properties.
    enum Origin: String, Codable, Sendable {
        case objective  // local, free signals (pronunciation GOP, fluency)
        case llm        // verified LLM-lane insights
    }

    var lens: Lens { Lens(rawValue: lensRaw) ?? .grammar }
    var origin: Origin { Origin(rawValue: originRaw) ?? .objective }
}

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
    /// Backing store for `kind` (CF-2) — which typed drill this item is practiced
    /// with. Stored as a String for CloudKit; defaulted to `.shadow` so every
    /// existing persisted item decodes unchanged. NOT a new `@Model` — an additive
    /// attribute, so the canonical schema stays at six types (GUARD invariant).
    var kindRaw: String = PracticeKind.shadow.rawValue
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

    /// Which typed drill (CF-2) this item is practiced with. Decoded from
    /// `kindRaw`; an unknown raw value falls back to `.shadow`.
    var kind: PracticeKind {
        get { PracticeKind(rawValue: kindRaw) ?? .shadow }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String? = nil,
        sourceText: String = "",
        segments: [String] = [],
        origin: Origin = .pasted,
        kind: PracticeKind = .shadow,
        sourceID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sourceText = sourceText
        self.segments = segments
        self.originRaw = origin.rawValue
        self.kindRaw = kind.rawValue
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
