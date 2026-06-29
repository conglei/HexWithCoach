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

    @Test func ranksBySeverityNotRawFrequency() {
        // Long notes were dominated by the most *frequent* sounds even when they were
        // mild. Ranking now leads with severity (more-negative GOP). Here all three are
        // plain consonants (no reduced vowels, no substitutions), so severity = -meanGOP:
        // l (9.0) > r (2.0) > v (1.5). With maxLessons: 2 the result is [l, r] — even
        // though /r/ is the most frequent (×3) and /l/ only occurs ×2.
        let result = PronunciationResult(words: [
            WordScore(word: "a", phonemes: [ph("r", gop: -2.0), ph("r", gop: -2.0), ph("r", gop: -2.0)]),
            WordScore(word: "b", phonemes: [ph("l", gop: -9.0), ph("l", gop: -9.0)]),
            WordScore(word: "c", phonemes: [ph("v", gop: -1.5)]),
        ])
        let lessons = PronunciationSummary.lessons(from: result, maxLessons: 2)
        #expect(lessons.count == 2)
        #expect(lessons[0].expected == "l")  // most severe (meanGOP -9.0)
        #expect(lessons[1].expected == "r")  // next severe (-2.0); v (-1.5) dropped
    }

    @Test func capsReducedVowelsToAtMostOne() {
        // Two reduced vowels (schwa /ə/ and /ɪ/) are very frequent and somewhat weak;
        // a single consonant /v/ is weaker per-instance but less frequent. Without the
        // cap, both reduced vowels would crowd the top 3 and bury teachable sounds.
        // Severity demotes reduced vowels by 1.0, and at most one may appear at all, so
        // the weak consonant is never crowded out by a *second* reduced vowel.
        let result = PronunciationResult(words: [
            WordScore(word: "about", phonemes: [
                ph("ə", gop: -3.0), ph("ə", gop: -3.0), ph("ə", gop: -3.0), ph("ə", gop: -3.0),
            ]),
            WordScore(word: "in", phonemes: [
                ph("ɪ", gop: -3.0), ph("ɪ", gop: -3.0), ph("ɪ", gop: -3.0),
            ]),
            WordScore(word: "very", phonemes: [ph("v", gop: -5.0)]),
        ])
        let lessons = PronunciationSummary.lessons(from: result, maxLessons: 3)
        let reducedCount = lessons.filter { ["ə", "ɪ", "ʊ", "ɐ", "ᵻ"].contains($0.expected) }.count
        #expect(reducedCount <= 1)
        // The weak consonant survives instead of a second reduced vowel.
        #expect(lessons.contains { $0.expected == "v" })
    }

    @Test func substitutionBumpsAboveUnclear() {
        // Two consonants with equal meanGOP: one has a dominant substitution ("you said
        // /n/"), the other is just unclear (no dominant actual). The concrete, more
        // actionable substitution should rank first thanks to the +1.0 severity bump.
        let result = PronunciationResult(words: [
            WordScore(word: "moment", phonemes: [
                ph("m", gop: -4.0, actual: "n"), ph("m", gop: -4.0, actual: "n"),
            ]),
            WordScore(word: "think", phonemes: [
                ph("θ", gop: -4.0, actual: "θ"), ph("θ", gop: -4.0, actual: "θ"),
            ]),
        ])
        let lessons = PronunciationSummary.lessons(from: result, maxLessons: 2)
        #expect(lessons.count == 2)
        #expect(lessons[0].expected == "m")   // has a substitution → more actionable
        #expect(lessons[0].actual == "n")
        #expect(lessons[1].expected == "θ")   // unclear, no dominant substitution
        #expect(lessons[1].actual == nil)
    }

    @Test func emptyWhenNothingWeak() {
        let result = PronunciationResult(words: [
            WordScore(word: "clear", phonemes: [ph("k", gop: 0.0), ph("l", gop: -0.2)]),
        ])
        #expect(PronunciationSummary.lessons(from: result).isEmpty)
    }
}
