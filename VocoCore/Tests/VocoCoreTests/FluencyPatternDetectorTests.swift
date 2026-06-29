import Foundation
import Testing
@testable import VocoCore

/// CI-2: the pure, deterministic fluency pattern detector — absolute thresholds +
/// recurrence + cold-start gate, with pace deliberately excluded from patterns.
/// All synthetic `FluencySignals` — no audio or model required.
struct FluencyPatternDetectorTests {

    // MARK: Builders

    /// A note that crosses the filler bar (habitual fillers).
    private func fillerHeavyNote() -> FluencyPatternDetector.Note {
        // 6 fillers over 30s → 12/min, well above the 8/min bar and ≥ minFillerCount.
        let s = FluencySignals(
            wordsPerMinute: 120, wordCount: 60, durationSec: 30,
            fillersPerMinute: 12, fillerCount: 6, restartCount: 0
        )
        return .init(transcriptID: UUID(), signals: s)
    }

    /// A note that crosses the restart bar.
    private func restartHeavyNote() -> FluencyPatternDetector.Note {
        let s = FluencySignals(
            wordsPerMinute: 120, wordCount: 60, durationSec: 30,
            fillersPerMinute: 0, fillerCount: 0, restartCount: 3
        )
        return .init(transcriptID: UUID(), signals: s)
    }

    /// A note that crosses the long-pause bar (requires pause stats).
    private func longPauseHeavyNote() -> FluencyPatternDetector.Note {
        let s = FluencySignals(
            wordsPerMinute: 60, wordCount: 30, durationSec: 30,
            fillersPerMinute: 0, fillerCount: 0, restartCount: 0,
            pauseCount: 6, meanPauseSec: 1.4, longPauseRate: 0.4, hasPauseStats: true
        )
        return .init(transcriptID: UUID(), signals: s)
    }

    /// A fluent note: nothing crosses any bar.
    private func cleanNote() -> FluencyPatternDetector.Note {
        let s = FluencySignals(
            wordsPerMinute: 130, wordCount: 65, durationSec: 30,
            fillersPerMinute: 1, fillerCount: 1, restartCount: 0,
            pauseCount: 1, meanPauseSec: 0.4, longPauseRate: 0.02, hasPauseStats: true
        )
        return .init(transcriptID: UUID(), signals: s)
    }

    private func fillerKey() -> String { FluencyPatternDetector.key(for: .fillers) }
    private func restartKey() -> String { FluencyPatternDetector.key(for: .restarts) }
    private func longPauseKey() -> String { FluencyPatternDetector.key(for: .longPauses) }

    // MARK: Cold-start gate

    @Test
    func coldStartGateEmitsNothingBelowMinNotes() {
        // Even blatant fillers in every note → no patterns below minNotes.
        let notes = (0 ..< (FluencyPatternDetector.minNotes - 1)).map { _ in fillerHeavyNote() }
        #expect(FluencyPatternDetector.detect(corpus: notes).isEmpty)
    }

    // MARK: Recurrence + absolute thresholds

    @Test
    func detectsRecurringFillersAcrossEnoughNotes() {
        // Enough notes, fillers cross the bar in each.
        let count = max(FluencyPatternDetector.minNotes, FluencyPatternDetector.minRecurringNotes)
        let notes = (0 ..< count).map { _ in fillerHeavyNote() }
        let obs = FluencyPatternDetector.detect(corpus: notes)

        #expect(obs.contains { $0.lens == .prosody && $0.key == fillerKey() })
        // No pace pattern is ever produced.
        #expect(!obs.contains { $0.key.contains("pace") })
    }

    @Test
    func detectsRecurringRestartsAndLongPauses() {
        // Pad with clean notes to clear the cold-start gate, then add enough
        // restart-heavy and long-pause-heavy notes to recur.
        var notes: [FluencyPatternDetector.Note] = []
        for _ in 0 ..< FluencyPatternDetector.minRecurringNotes { notes.append(restartHeavyNote()) }
        for _ in 0 ..< FluencyPatternDetector.minRecurringNotes { notes.append(longPauseHeavyNote()) }
        // Ensure cold-start passes regardless.
        while notes.count < FluencyPatternDetector.minNotes { notes.append(cleanNote()) }

        let obs = FluencyPatternDetector.detect(corpus: notes)
        #expect(obs.contains { $0.key == restartKey() })
        #expect(obs.contains { $0.key == longPauseKey() })
    }

    @Test
    func recurrenceRequiresEnoughDistinctNotes() {
        // Only (minRecurringNotes - 1) filler-heavy notes → below recurrence even
        // though the cold-start gate is satisfied by clean padding.
        var notes: [FluencyPatternDetector.Note] = []
        for _ in 0 ..< (FluencyPatternDetector.minRecurringNotes - 1) { notes.append(fillerHeavyNote()) }
        while notes.count < FluencyPatternDetector.minNotes { notes.append(cleanNote()) }

        let obs = FluencyPatternDetector.detect(corpus: notes)
        #expect(!obs.contains { $0.key == fillerKey() })
    }

    @Test
    func fluentCorpusYieldsNoPatterns() {
        let notes = (0 ..< (FluencyPatternDetector.minNotes + 3)).map { _ in cleanNote() }
        #expect(FluencyPatternDetector.detect(corpus: notes).isEmpty)
    }

    // MARK: Pace is never a pattern

    @Test
    func paceIsNeverAPattern() {
        // Wildly fast AND wildly slow notes, all otherwise fluent. Pace deviation
        // must NEVER produce a pattern (design §2 — pace is informational only).
        var notes: [FluencyPatternDetector.Note] = []
        for _ in 0 ..< (FluencyPatternDetector.minNotes + 2) {
            let fast = FluencySignals(
                wordsPerMinute: 400, wordCount: 200, durationSec: 30,
                fillersPerMinute: 0, fillerCount: 0, restartCount: 0
            )
            notes.append(.init(transcriptID: UUID(), signals: fast))
        }
        let obs = FluencyPatternDetector.detect(corpus: notes)
        #expect(obs.isEmpty)
        // And `Kind` itself has no pace case.
        #expect(!FluencyPatternDetector.Kind.allCases.contains { $0.rawValue.contains("pace") })
        #expect(!FluencyPatternDetector.Kind.allCases.contains { $0.rawValue.contains("wpm") })
    }

    // MARK: Short-note guard for fillers

    @Test
    func shortNoteWithOneFillerDoesNotFlagFillers() {
        // A 3-second note with a single "um" spikes to 20 fillers/min, but the
        // absolute filler COUNT (1) is below minFillerCount, so it never flags —
        // and thus never recurs into a pattern.
        var notes: [FluencyPatternDetector.Note] = []
        for _ in 0 ..< (FluencyPatternDetector.minNotes + 2) {
            let s = FluencySignals(
                wordsPerMinute: 100, wordCount: 5, durationSec: 3,
                fillersPerMinute: 20, fillerCount: 1, restartCount: 0
            )
            notes.append(.init(transcriptID: UUID(), signals: s))
        }
        #expect(!FluencyPatternDetector.detect(corpus: notes).contains { $0.key == fillerKey() })
    }

    // MARK: Pause kind ignores notes without timings

    @Test
    func longPausesIgnoreNotesWithoutPauseStats() {
        // longPauseRate is set high but hasPauseStats is false (a placeholder, not
        // a measurement) — these notes must NOT count toward the long-pause kind.
        var notes: [FluencyPatternDetector.Note] = []
        for _ in 0 ..< (FluencyPatternDetector.minNotes + 2) {
            let s = FluencySignals(
                wordsPerMinute: 100, wordCount: 50, durationSec: 30,
                fillersPerMinute: 0, fillerCount: 0, restartCount: 0,
                pauseCount: 0, meanPauseSec: 0, longPauseRate: 0.9, hasPauseStats: false
            )
            notes.append(.init(transcriptID: UUID(), signals: s))
        }
        #expect(!FluencyPatternDetector.detect(corpus: notes).contains { $0.key == longPauseKey() })
    }

    // MARK: Determinism + profile integration

    @Test
    func detectIsDeterministic() {
        let notes = (0 ..< (FluencyPatternDetector.minNotes + 2)).map { _ in fillerHeavyNote() }
        #expect(FluencyPatternDetector.detect(corpus: notes) == FluencyPatternDetector.detect(corpus: notes))
    }

    @Test
    func patternsMergeIntoProfileViaIntegrate() {
        let notes = (0 ..< (FluencyPatternDetector.minNotes + 2)).map { _ in fillerHeavyNote() }
        let obs = FluencyPatternDetector.detect(corpus: notes)
        #expect(!obs.isEmpty)

        var profile = LearnerProfile()
        profile.integrate(obs, at: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(profile.patterns.contains { $0.lens == .prosody && $0.key == fillerKey() })
    }
}
