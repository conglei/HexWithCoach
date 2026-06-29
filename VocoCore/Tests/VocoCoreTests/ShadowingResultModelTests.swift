import Foundation
import Testing
@testable import VocoCore

/// SR-2 — pure presentation logic for the shadowing result screen: per-word
/// good/close/off bucketing, the focused issue selection/ordering (via
/// `PhonemeAnchor`), and the dual-signal verdict (ASR match vs GOP issues kept
/// separate). Model-free / deterministic.
struct ShadowingResultModelTests {

    private func ph(_ symbol: String, gop: Double, actual: String? = nil) -> PhonemeScore {
        PhonemeScore(symbol: symbol, start: 0, end: 0.02, gop: gop, actualSymbol: actual)
    }

    // MARK: - Per-word quality bucketing

    @Test func wordQualityBucketsAtCutoffs() {
        // good ≥ -0.3, close ≥ -1.0, else off — boundary-exact.
        #expect(ShadowingResult.WordQuality.of(meanGOP: 0.0) == .good)
        #expect(ShadowingResult.WordQuality.of(meanGOP: -0.3) == .good)
        #expect(ShadowingResult.WordQuality.of(meanGOP: -0.31) == .close)
        #expect(ShadowingResult.WordQuality.of(meanGOP: -1.0) == .close)
        #expect(ShadowingResult.WordQuality.of(meanGOP: -1.01) == .off)
        #expect(ShadowingResult.WordQuality.of(meanGOP: -9.0) == .off)
    }

    @Test func perWordQualityFromResult() {
        let result = PronunciationResult(words: [
            WordScore(word: "the", phonemes: [ph("ð", gop: -0.1), ph("ə", gop: -0.2)]), // mean -0.15 → good
            WordScore(word: "robe", phonemes: [ph("ɹ", gop: -0.4), ph("oʊ", gop: -0.6), ph("b", gop: -0.5)]), // mean -0.5 → close
        ])
        let words = ShadowingResult.words(target: "The robe", result: result)
        #expect(words.count == 2)
        #expect(words[0].text == "The")
        #expect(words[0].quality == .good)
        #expect(words[1].quality == .close)
        #expect(words[1].phonemes.count == 3)
    }

    @Test func offWordIsFlagged() {
        let result = PronunciationResult(words: [
            WordScore(word: "thought", phonemes: [ph("θ", gop: -3.0, actual: "t"), ph("ɔ", gop: -2.5), ph("t", gop: -0.2)]),
        ])
        let words = ShadowingResult.words(target: "thought", result: result)
        #expect(words[0].quality == .off)
        #expect(words[0].isFlagged)
    }

    @Test func unscoredWordsWhenNoResult() {
        let words = ShadowingResult.words(target: "Hello there friend", result: nil)
        #expect(words.count == 3)
        #expect(words.allSatisfy { $0.quality == nil })
        #expect(words.allSatisfy { !$0.isFlagged })
        #expect(words.map(\.text) == ["Hello", "there", "friend"])
    }

    @Test func outOfDictionaryWordRendersPlain() {
        // The analyzer skipped "zzqq" (no scored word for it); it must still render
        // as a plain token with nil quality while the scored word pairs correctly.
        let result = PronunciationResult(words: [
            WordScore(word: "cat", phonemes: [ph("k", gop: -0.1), ph("æ", gop: -0.1), ph("t", gop: -0.1)]),
        ])
        let words = ShadowingResult.words(target: "zzqq cat", result: result)
        #expect(words.count == 2)
        #expect(words[0].text == "zzqq")
        #expect(words[0].quality == nil)
        #expect(words[1].text == "cat")
        #expect(words[1].quality == .good)
    }

    @Test func punctuationDoesNotBreakPairing() {
        let result = PronunciationResult(words: [
            WordScore(word: "robe", phonemes: [ph("ɹ", gop: -0.1), ph("oʊ", gop: -0.1), ph("b", gop: -0.1)]),
        ])
        // Target token carries a trailing comma + different casing.
        let words = ShadowingResult.words(target: "Robe,", result: result)
        #expect(words.count == 1)
        #expect(words[0].text == "Robe,")
        #expect(words[0].quality == .good)
    }

    // MARK: - Focused issues (ordering + PhonemeAnchor phrasing)

    @Test func issuesUsePhonemeAnchorSubstitutionText() {
        // /oʊ/ said as /ɑ/ in "robe" — the anchor gives the as-in exemplars + tip.
        let result = PronunciationResult(words: [
            WordScore(word: "robe", phonemes: [ph("oʊ", gop: -3.0, actual: "ɑ")]),
        ])
        let issues = ShadowingResult.issues(from: result)
        #expect(issues.count == 1)
        let issue = issues[0]
        #expect(issue.word == "robe")
        #expect(issue.expected == "oʊ")
        #expect(issue.actual == "ɑ")
        #expect(issue.detail == "you said /ɑ/ (as in \"rob\") — aim for /oʊ/ (as in \"robe\")")
        #expect(issue.tip == PhonemeAnchor.guide(for: "oʊ")?.tip)
        #expect(issue.tip != nil)
    }

    @Test func issuesCappedAndOrderedBySeverity() {
        // Three concrete weak substitutions of increasing severity + one good sound.
        let result = PronunciationResult(words: [
            WordScore(word: "alpha", phonemes: [ph("f", gop: -1.5, actual: "p")]),
            WordScore(word: "bravo", phonemes: [ph("v", gop: -3.0, actual: "b")]),
            WordScore(word: "charlie", phonemes: [ph("tʃ", gop: -5.0, actual: "ʃ")]),
            WordScore(word: "delta", phonemes: [ph("d", gop: -0.1, actual: "d")]), // good → excluded
        ])
        let issues = ShadowingResult.issues(from: result, limit: 2)
        #expect(issues.count == 2)
        // Most severe (most-negative GOP) first.
        #expect(issues[0].expected == "tʃ")
        #expect(issues[1].expected == "v")
    }

    @Test func noIssuesWhenEverythingClear() {
        let result = PronunciationResult(words: [
            WordScore(word: "yes", phonemes: [ph("j", gop: -0.1), ph("ɛ", gop: -0.1), ph("s", gop: -0.1)]),
        ])
        #expect(ShadowingResult.issues(from: result).isEmpty)
    }

    @Test func noIssuesWhenNoResult() {
        #expect(ShadowingResult.issues(from: nil).isEmpty)
    }

    @Test func issueFallsBackForUnclearSound() {
        // Weak but the model still heard the right sound — no dominant substitution.
        // Detail falls back to an "aim for" phrasing rather than a bogus "you said".
        let result = PronunciationResult(words: [
            WordScore(word: "think", phonemes: [ph("θ", gop: -4.0, actual: "θ")]),
        ])
        let issues = ShadowingResult.issues(from: result)
        #expect(issues.count == 1)
        #expect(issues[0].actual == nil)
        #expect(issues[0].detail == "aim for /θ/ (as in \"think\")")
    }

    // MARK: - Dual-signal verdict

    @Test func verdictNeverClaimsWinWithIssues() {
        let v = ShadowingResult.verdict(score: 1.0, issueCount: 3)
        #expect(v.rightWords)
        #expect(!v.isWin)
        #expect(v.soundIssueCount == 3)
        #expect(v.headline == "Almost there — 3 sounds to polish")
    }

    @Test func verdictWinOnlyWithRightWordsAndZeroIssues() {
        let v = ShadowingResult.verdict(score: 1.0, issueCount: 0)
        #expect(v.isWin)
        #expect(v.headline == "Nailed it!")
    }

    @Test func verdictSingularSound() {
        let v = ShadowingResult.verdict(score: 0.9, issueCount: 1)
        #expect(v.headline == "Almost there — 1 sound to polish")
    }

    @Test func verdictWrongWords() {
        let v = ShadowingResult.verdict(score: 0.2, issueCount: 2)
        #expect(!v.rightWords)
        #expect(!v.isWin)
        #expect(v.headline == "Let's try that again — 2 sounds to polish")
    }

    @Test func verdictWrongWordsNoGOP() {
        let v = ShadowingResult.verdict(score: 0.2, issueCount: nil)
        #expect(!v.rightWords)
        #expect(v.headline == "Let's try that again")
    }

    @Test func verdictRightWordsNoGOP() {
        // GOP unavailable (no model / OOD): rest on the ASR match, hide the sound signal.
        let v = ShadowingResult.verdict(score: 0.95, issueCount: nil)
        #expect(v.rightWords)
        #expect(!v.isWin) // can't claim a win without measuring the sounds
        #expect(v.soundIssueCount == nil)
        #expect(v.headline == "Got the words")
    }
}
