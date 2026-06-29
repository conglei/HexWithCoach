import Foundation
import Testing
@testable import VocoCore

/// Tests the "sounds to work on" summary: grouping weak phonemes by expected
/// sound, the most-common substitution (expected → actual), example words, and
/// ranking. Pure / model-free.
struct PronunciationSummaryTests {

    private func ph(_ symbol: String, gop: Double, actual: String? = nil) -> PhonemeScore {
        PhonemeScore(symbol: symbol, start: 0, end: 0.02, gop: gop, actualSymbol: actual)
    }

    @Test func groupsWeakPhonemesWithSubstitutionAndExamples() {
        let result = PronunciationResult(words: [
            WordScore(word: "implement", phonemes: [
                ph("ɪ", gop: 0.0, actual: "ɪ"),        // good → ignored
                ph("m", gop: -9.3, actual: "n"),        // weak, said /n/
            ]),
            WordScore(word: "moment", phonemes: [
                ph("m", gop: -8.0, actual: "n"),        // weak, said /n/
            ]),
        ])
        let lessons = PronunciationSummary.lessons(from: result)
        #expect(lessons.count == 1)
        let m = lessons[0]
        #expect(m.expected == "m")
        #expect(m.actual == "n")
        #expect(m.count == 2)
        #expect(m.exampleWords == ["implement", "moment"])
    }

    @Test func omitsSubstitutionWhenSoundAttemptedButUnclear() {
        // Weak, but the model still "heard" the right sound (no dominant substitution).
        let result = PronunciationResult(words: [
            WordScore(word: "think", phonemes: [ph("θ", gop: -4.0, actual: "θ")]),
        ])
        let lessons = PronunciationSummary.lessons(from: result)
        #expect(lessons.count == 1)
        #expect(lessons[0].expected == "θ")
        #expect(lessons[0].actual == nil)
    }

    @Test func ranksByFrequencyThenSeverityAndCaps() {
        let result = PronunciationResult(words: [
            WordScore(word: "a", phonemes: [ph("r", gop: -2.0), ph("r", gop: -2.0), ph("r", gop: -2.0)]),
            WordScore(word: "b", phonemes: [ph("l", gop: -9.0), ph("l", gop: -9.0)]),
            WordScore(word: "c", phonemes: [ph("v", gop: -1.5)]),
        ])
        let lessons = PronunciationSummary.lessons(from: result, maxLessons: 2)
        #expect(lessons.count == 2)
        #expect(lessons[0].expected == "r")  // most frequent (3)
        #expect(lessons[1].expected == "l")  // next frequent (2), v (1) dropped
    }

    @Test func emptyWhenNothingWeak() {
        let result = PronunciationResult(words: [
            WordScore(word: "clear", phonemes: [ph("k", gop: 0.0), ph("l", gop: -0.2)]),
        ])
        #expect(PronunciationSummary.lessons(from: result).isEmpty)
    }
}
