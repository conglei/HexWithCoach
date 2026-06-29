import Foundation

/// The pure state machine behind the paste-to-practice session (PR-3): walk the
/// segments one at a time, record each segment's score as it finishes, and at the
/// end produce the single attempt payload (`perSegmentScores` + averaged GOP
/// delta) that gets persisted as a `PracticeAttempt`.
///
/// Kept out of the SwiftUI view (which only renders + persists) so the advancement
/// and payload logic is unit-testable under `swift test` — guarding against the
/// "session never advances / never saves" regression that motivated extracting it.
public struct PasteSessionState: Equatable, Sendable {
    /// The speakable segments, in reading order.
    public let segments: [String]
    /// Index of the segment currently being shadowed; equals `segments.count`
    /// once every segment is done (`isComplete`).
    public private(set) var index: Int = 0
    /// Per-segment ASR match scores, appended as each segment finishes.
    public private(set) var scores: [Double] = []
    /// GOP deltas reported per segment (only when the pronunciation model produced
    /// a comparison); averaged into the attempt payload.
    public private(set) var gopDeltas: [Double] = []

    public init(segments: [String]) {
        self.segments = segments
    }

    /// The segment to shadow now, or nil when the session is complete.
    public var currentSegment: String? {
        index < segments.count ? segments[index] : nil
    }

    /// True once every segment has been finished.
    public var isComplete: Bool { index >= segments.count }

    /// Record the outcome of the current segment and advance to the next. A nil
    /// `gopDelta` (no pronunciation model / first attempt) contributes no delta.
    /// No-op once the session is already complete.
    public mutating func recordCurrent(score: Double, gopDelta: Double? = nil) {
        guard !isComplete else { return }
        scores.append(score)
        if let gopDelta { gopDeltas.append(gopDelta) }
        index += 1
    }

    /// The single attempt payload for the whole session: every per-segment score
    /// plus the mean of the reported GOP deltas (nil when none were reported).
    public var attemptPayload: AttemptPayload {
        let avgDelta = gopDeltas.isEmpty ? nil : gopDeltas.reduce(0, +) / Double(gopDeltas.count)
        return AttemptPayload(perSegmentScores: scores, gopDelta: avgDelta)
    }

    /// Average ASR match across the recorded segments (0 when none recorded).
    public var averageScore: Double {
        scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    /// The data persisted as one `PracticeAttempt` at session end. Mirrors
    /// `PracticeAttempt`'s `perSegmentScores` / `gopDelta` without depending on
    /// SwiftData, so it stays in VocoCore.
    public struct AttemptPayload: Equatable, Sendable {
        public let perSegmentScores: [Double]
        public let gopDelta: Double?

        public init(perSegmentScores: [Double], gopDelta: Double?) {
            self.perSegmentScores = perSegmentScores
            self.gopDelta = gopDelta
        }
    }
}
