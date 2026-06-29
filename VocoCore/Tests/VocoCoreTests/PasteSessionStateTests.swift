import Testing
@testable import VocoCore

/// Behavior spec for the paste-to-practice session state machine (PR-3). Guards
/// the regression where the drill never advanced past segment 0 and never
/// produced an attempt: these pin that a session walks every segment exactly once
/// and yields one attempt payload with one score per segment.
@Suite struct PasteSessionStateTests {

    @Test func twoSegmentSessionAdvancesThroughBothAndProducesOneAttempt() {
        var state = PasteSessionState(segments: ["First line.", "Second line."])

        // Segment 0.
        #expect(state.currentSegment == "First line.")
        #expect(!state.isComplete)
        state.recordCurrent(score: 0.9, gopDelta: 0.2)

        // Advances to segment 1 (did NOT stall or jump to complete).
        #expect(state.index == 1)
        #expect(state.currentSegment == "Second line.")
        #expect(!state.isComplete)
        state.recordCurrent(score: 0.7, gopDelta: 0.4)

        // Now complete: every segment was visited once.
        #expect(state.isComplete)
        #expect(state.currentSegment == nil)

        // Exactly one attempt payload, one score per segment, averaged GOP delta.
        let payload = state.attemptPayload
        #expect(payload.perSegmentScores == [0.9, 0.7])
        #expect(payload.gopDelta == 0.30000000000000004)   // (0.2 + 0.4) / 2
    }

    @Test func singleSegmentSessionAlsoCompletesAndProducesOneAttempt() {
        var state = PasteSessionState(segments: ["Only line."])
        #expect(state.currentSegment == "Only line.")
        #expect(!state.isComplete)

        state.recordCurrent(score: 0.85)

        #expect(state.isComplete)
        #expect(state.currentSegment == nil)
        let payload = state.attemptPayload
        #expect(payload.perSegmentScores == [0.85])
        #expect(payload.gopDelta == nil)   // no GOP reported → nil, not 0
    }

    @Test func nilGopDeltasYieldNilAttemptDelta() {
        var state = PasteSessionState(segments: ["a", "b"])
        state.recordCurrent(score: 0.5, gopDelta: nil)
        state.recordCurrent(score: 0.6, gopDelta: nil)
        #expect(state.attemptPayload.gopDelta == nil)
        #expect(state.attemptPayload.perSegmentScores == [0.5, 0.6])
    }

    @Test func recordingPastCompletionIsANoOp() {
        var state = PasteSessionState(segments: ["only"])
        state.recordCurrent(score: 0.5)
        #expect(state.isComplete)
        // Extra calls (e.g. a stray onScored) must not append phantom scores.
        state.recordCurrent(score: 0.9)
        #expect(state.scores == [0.5])
        #expect(state.index == 1)
    }

    @Test func averageScoreReflectsRecordedSegments() {
        var state = PasteSessionState(segments: ["a", "b"])
        #expect(state.averageScore == 0)   // nothing recorded yet
        state.recordCurrent(score: 0.4)
        state.recordCurrent(score: 0.6)
        #expect(state.averageScore == 0.5)
    }
}
