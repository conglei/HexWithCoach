import Foundation
import Testing
@testable import HexCore

struct FluencySignalsTests {
    @Test
    func computesPaceAndFillerRateLocally() {
        // 13 words over 30s → 26 wpm. Fillers: "um", "uh", "you know", "like" = 4 → 8/min.
        let transcript = "um so I was uh thinking you know about this like project today"
        let signals = FluencyAnalyzer.analyze(transcript: transcript, durationSec: 30)

        #expect(signals.wordCount == 13)
        #expect(signals.wordsPerMinute == 26.0)        // 13 / (30/60)
        #expect(signals.fillerCount == 4)              // um, uh, you know, like
        #expect(signals.fillersPerMinute == 8.0)       // 4 / 0.5
    }

    @Test
    func fillersMatchOnWordBoundariesNotSubstrings() {
        // "likely" and "summary" must NOT trip "like" / "um".
        let transcript = "I will likely finish the summary tomorrow"
        let signals = FluencyAnalyzer.analyze(transcript: transcript, durationSec: 60)
        #expect(signals.fillerCount == 0)
    }

    @Test
    func zeroOrNegativeDurationYieldsZeroRatesAndDoesNotCrash() {
        let transcript = "um uh some words here"
        let zero = FluencyAnalyzer.analyze(transcript: transcript, durationSec: 0)
        #expect(zero.wordsPerMinute == 0)
        #expect(zero.fillersPerMinute == 0)
        #expect(zero.wordCount == 5)   // still counts words
        #expect(zero.fillerCount == 2) // still counts fillers

        let negative = FluencyAnalyzer.analyze(transcript: transcript, durationSec: -10)
        #expect(negative.wordsPerMinute == 0)
        #expect(negative.fillersPerMinute == 0)
        #expect(negative.durationSec == 0) // clamped
    }

    @Test
    func emptyTranscriptIsSafe() {
        let signals = FluencyAnalyzer.analyze(transcript: "   ", durationSec: 10)
        #expect(signals.wordCount == 0)
        #expect(signals.wordsPerMinute == 0)
        #expect(signals.fillerCount == 0)
    }

    @Test
    func restartHeuristicCatchesRepeatedWord() {
        let signals = FluencyAnalyzer.analyze(transcript: "the the cat sat", durationSec: 10)
        #expect(signals.restartCount == 1)
    }

    @Test
    func restartHeuristicCatchesDashSelfCorrection() {
        // Em-dash self-correction with more speech after it.
        let signals = FluencyAnalyzer.analyze(transcript: "I want\u{2014} I need coffee", durationSec: 10)
        #expect(signals.restartCount >= 1)
    }

    @Test
    func cleanSpeechHasNoRestarts() {
        let signals = FluencyAnalyzer.analyze(transcript: "I would like a coffee please", durationSec: 10)
        #expect(signals.restartCount == 0)
    }

    @Test
    func pauseStatsProducedWhenWordTimingsSupplied() {
        // Gaps (end→start): 0.1 (no pause), 0.5 (pause), 1.5 (long pause).
        let timings = [
            WordTiming(word: "I", start: 0.0, end: 0.4),
            WordTiming(word: "was", start: 0.5, end: 0.9),   // gap 0.1
            WordTiming(word: "really", start: 1.4, end: 1.8), // gap 0.5  → pause
            WordTiming(word: "tired", start: 3.3, end: 3.7),  // gap 1.5  → pause + long
        ]
        let signals = FluencyAnalyzer.analyze(
            transcript: "I was really tired", durationSec: 4, wordTimings: timings
        )

        #expect(signals.hasPauseStats)
        #expect(signals.pauseCount == 2)                     // 0.5 and 1.5
        #expect(abs(signals.meanPauseSec - 1.0) < 1e-9)      // (0.5 + 1.5) / 2
        #expect(abs(signals.longPauseRate - (1.0 / 3.0)) < 1e-9) // 1 of 3 gaps > 1.0s
    }

    @Test
    func pauseStatsAbsentWhenNoWordTimings() {
        let signals = FluencyAnalyzer.analyze(transcript: "I was really tired", durationSec: 4)
        #expect(signals.hasPauseStats == false)
        #expect(signals.pauseCount == 0)
        #expect(signals.meanPauseSec == 0)
        #expect(signals.longPauseRate == 0)
        // And the pause keys are omitted from the metrics dict.
        #expect(signals.metrics["pauseCount"] == nil)
    }

    @Test
    func metricsDictionaryContainsExpectedKeys() {
        let signals = FluencyAnalyzer.analyze(transcript: "um hello there", durationSec: 30)
        let m = signals.metrics
        for key in ["wordsPerMinute", "fillersPerMinute", "fillerCount", "restartCount", "wordCount", "durationSec"] {
            #expect(m[key] != nil, "missing metric key \(key)")
        }
        // Pause keys present only with timings.
        #expect(m["pauseCount"] == nil)

        let withPauses = FluencyAnalyzer.analyze(
            transcript: "um hello there", durationSec: 30,
            wordTimings: [
                WordTiming(word: "um", start: 0, end: 0.3),
                WordTiming(word: "hello", start: 1.0, end: 1.4),
                WordTiming(word: "there", start: 1.5, end: 1.9),
            ]
        )
        for key in ["pauseCount", "meanPauseSec", "longPauseRate"] {
            #expect(withPauses.metrics[key] != nil, "missing pause metric key \(key)")
        }
    }

    @Test
    func metricsAreRounded() {
        // 7 words over 13s → 32.307... wpm → rounds to 32.3.
        let signals = FluencyAnalyzer.analyze(
            transcript: "one two three four five six seven", durationSec: 13
        )
        #expect(signals.metrics["wordsPerMinute"] == 32.3)
        // Raw field stays precise.
        #expect(signals.wordsPerMinute > 32.3)
    }

    @Test
    func roundTripsThroughCodable() throws {
        let signals = FluencyAnalyzer.analyze(
            transcript: "um I I think you know it's like fine",
            durationSec: 20,
            wordTimings: [
                WordTiming(word: "um", start: 0, end: 0.4),
                WordTiming(word: "think", start: 1.0, end: 1.4),
            ]
        )
        let data = try JSONEncoder().encode(signals)
        let restored = try JSONDecoder().decode(FluencySignals.self, from: data)
        #expect(restored == signals)
    }
}
