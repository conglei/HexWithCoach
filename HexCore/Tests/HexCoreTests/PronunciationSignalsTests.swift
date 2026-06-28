import Foundation
import Testing
@testable import HexCore

/// CI-3: pronunciation signals summary, per-speaker GOP calibration, and the
/// pure per-speaker-relative + recurrence + cold-start pattern detector. All
/// synthetic GOP data — no Core ML model required.
struct PronunciationSignalsTests {

    // MARK: Builders

    private func phoneme(_ symbol: String, gop: Double) -> PhonemeScore {
        PhonemeScore(symbol: symbol, start: 0, end: 0.02, gop: gop)
    }

    private func word(_ text: String, _ phonemes: [(String, Double)]) -> WordScore {
        WordScore(word: text, phonemes: phonemes.map { phoneme($0.0, gop: $0.1) })
    }

    // MARK: PronunciationSignals summary

    @Test
    func signalsSummariseOverallPerPhonemeAndWorstWords() {
        let result = PronunciationResult(words: [
            word("think", [("θ", -2.0), ("ɪ", -0.1), ("ŋ", -0.2), ("k", -0.1)]),
            word("the", [("ð", -1.8), ("ə", -0.1)]),
        ])
        let s = PronunciationSignals(result: result)

        // Overall = mean over all 6 phonemes.
        let expected = (-2.0 + -0.1 + -0.2 + -0.1 + -1.8 + -0.1) / 6
        #expect(abs(s.overallGOP - expected) < 1e-9)

        // Per-phoneme is one entry per distinct symbol, sorted by symbol.
        #expect(s.perPhoneme.map(\.symbol) == s.perPhoneme.map(\.symbol).sorted())
        #expect(s.perPhoneme.contains { $0.symbol == "θ" && $0.count == 1 })

        // Worst words, worst-first: "think" (θ -2.0) before "the" (ð -1.8).
        #expect(s.worstWords.first?.word == "think")
        #expect(s.worstWords.first?.worstPhoneme == "θ")
        #expect(s.worstWords.first?.gop == -2.0)
    }

    @Test
    func emptyResultYieldsZeroSignals() {
        let s = PronunciationSignals(result: PronunciationResult(words: []))
        #expect(s.overallGOP == 0)
        #expect(s.perPhoneme.isEmpty)
        #expect(s.worstWords.isEmpty)
    }

    @Test
    func signalsRoundTripCodable() throws {
        let result = PronunciationResult(words: [word("a", [("æ", -0.5)])])
        let s = PronunciationSignals(result: result)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PronunciationSignals.self, from: data)
        #expect(back == s)
    }

    @Test
    func pronunciationResultRoundTripsCodable() throws {
        let result = PronunciationResult(words: [
            word("think", [("θ", -2.0), ("ɪ", -0.1)]),
        ])
        let data = try JSONEncoder().encode(result)
        let back = try JSONDecoder().decode(PronunciationResult.self, from: data)
        #expect(back == result)
    }

    // MARK: Calibration

    @Test
    func calibrationComputesPerSpeakerBaseline() {
        // Two notes; θ is consistently the worst phoneme for this speaker.
        let n1 = PronunciationSignals(result: PronunciationResult(words: [
            word("think", [("θ", -3.0), ("ɪ", -0.1), ("k", -0.1)]),
        ]))
        let n2 = PronunciationSignals(result: PronunciationResult(words: [
            word("thought", [("θ", -2.6), ("ɔ", -0.2), ("t", -0.1)]),
        ]))
        let cal = PronunciationCalibration(corpus: [n1, n2])

        #expect(cal.noteCount == 2)
        let theta = cal.baselines.first { $0.symbol == "θ" }
        #expect(theta != nil)
        #expect(abs((theta?.meanGOP ?? 0) - (-2.8)) < 1e-9)
        #expect(theta?.totalCount == 2)
        #expect(theta?.noteCount == 2)

        // θ is the worst → relativeRank near 0.
        let rank = cal.relativeRank(of: "θ")
        #expect(rank != nil)
        #expect((rank ?? 1) <= 0.25)
        // A good phoneme ranks high.
        #expect((cal.relativeRank(of: "k") ?? 0) > 0.25)
        // Unknown symbol → nil.
        #expect(cal.relativeRank(of: "zzz") == nil)
    }

    // MARK: Detector — cold-start gate

    @Test
    func coldStartGateEmitsNothingBelowMinNotes() {
        // Even with a blatantly bad phoneme, too few notes → no patterns.
        let notes = (0 ..< (PronunciationPatternDetector.minNotes - 1)).map { _ in
            badThetaNote()
        }
        let obs = PronunciationPatternDetector.detect(corpus: notes)
        #expect(obs.isEmpty)
    }

    // MARK: Detector — recurrence + relative ranking

    @Test
    func detectsRecurringWeakPhonemeAcrossEnoughNotes() {
        // Enough notes, θ is consistently the speaker's worst and recurs.
        var notes: [PronunciationPatternDetector.Note] = []
        for _ in 0 ..< max(PronunciationPatternDetector.minNotes, PronunciationPatternDetector.minRecurringNotes) {
            notes.append(badThetaNote())
        }
        let obs = PronunciationPatternDetector.detect(corpus: notes)

        #expect(obs.contains { $0.lens == .pronunciation && $0.key == PronunciationPatternDetector.key(forPhoneme: "θ") })
        let theta = obs.first { $0.key == PronunciationPatternDetector.key(forPhoneme: "θ") }
        #expect(theta?.example.span == "think")   // carries the learner's own word
    }

    @Test
    func absoluteGOPAloneNeverTriggersAPattern() {
        // Every phoneme is uniformly very negative (a quiet mic / accent): no
        // phoneme is relatively worse than the others, so NOTHING is flagged,
        // even though absolute GOP is terrible across many notes.
        var notes: [PronunciationPatternDetector.Note] = []
        for _ in 0 ..< (PronunciationPatternDetector.minNotes + 2) {
            let result = PronunciationResult(words: [
                word("uniform", [("j", -5.0), ("u", -5.0), ("n", -5.0), ("ɪ", -5.0), ("f", -5.0), ("ɔ", -5.0), ("m", -5.0)]),
            ])
            notes.append(.init(transcriptID: UUID(), signals: PronunciationSignals(result: result)))
        }
        let obs = PronunciationPatternDetector.detect(corpus: notes)
        #expect(obs.isEmpty)
    }

    @Test
    func recurrenceRequiresEnoughDistinctNotes() {
        // One note repeated content can't manufacture a pattern: pile all the
        // bad-θ instances into a SINGLE note. Instances may be high but the note
        // count is 1, below minRecurringNotes.
        var bigPhonemes: [(String, Double)] = []
        for _ in 0 ..< (PronunciationPatternDetector.minInstances + 2) {
            bigPhonemes.append(("θ", -3.0))
        }
        bigPhonemes.append(contentsOf: [("ɪ", -0.1), ("k", -0.1)])
        let oneBadNote = PronunciationPatternDetector.Note(
            transcriptID: UUID(),
            signals: PronunciationSignals(result: PronunciationResult(words: [word("think", bigPhonemes)]))
        )
        // Pad with clean notes so the cold-start gate passes.
        var notes = [oneBadNote]
        for _ in 0 ..< PronunciationPatternDetector.minNotes {
            notes.append(cleanNote())
        }
        let obs = PronunciationPatternDetector.detect(corpus: notes)
        #expect(!obs.contains { $0.key == PronunciationPatternDetector.key(forPhoneme: "θ") })
    }

    @Test
    func detectIsDeterministic() {
        let notes = (0 ..< (PronunciationPatternDetector.minNotes + 2)).map { _ in badThetaNote() }
        let a = PronunciationPatternDetector.detect(corpus: notes)
        let b = PronunciationPatternDetector.detect(corpus: notes)
        #expect(a == b)
    }

    @Test
    func patternsMergeIntoProfileViaIntegrate() {
        let notes = (0 ..< (PronunciationPatternDetector.minNotes + 2)).map { _ in badThetaNote() }
        let obs = PronunciationPatternDetector.detect(corpus: notes)
        #expect(!obs.isEmpty)

        var profile = LearnerProfile()
        profile.integrate(obs, at: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(profile.patterns.contains { $0.lens == .pronunciation })
    }

    // MARK: Fixtures

    /// A note where θ ("think") is the clear per-note worst, plus good phonemes.
    private func badThetaNote() -> PronunciationPatternDetector.Note {
        let result = PronunciationResult(words: [
            word("think", [("θ", -3.0), ("ɪ", -0.1), ("ŋ", -0.1), ("k", -0.1)]),
            word("today", [("t", -0.1), ("ə", -0.1), ("d", -0.1), ("eɪ", -0.1)]),
        ])
        return .init(transcriptID: UUID(), signals: PronunciationSignals(result: result))
    }

    /// A note with uniformly good phonemes (nothing relatively weak).
    private func cleanNote() -> PronunciationPatternDetector.Note {
        let result = PronunciationResult(words: [
            word("today", [("t", -0.1), ("ə", -0.1), ("d", -0.1), ("eɪ", -0.1)]),
        ])
        return .init(transcriptID: UUID(), signals: PronunciationSignals(result: result))
    }
}
