import Testing
@testable import HexCore

/// CI-11 — closed-loop shadowing GOP re-scoring. Pure comparison logic, exercised
/// with synthetic GOP (no model needed).
struct ShadowingGOPComparisonTests {
    /// Build a single-word `PronunciationResult` from (symbol, gop) pairs.
    private func result(_ word: String, _ phonemes: [(String, Double)]) -> PronunciationResult {
        let scores = phonemes.map { PhonemeScore(symbol: $0.0, start: 0, end: 0.02, gop: $0.1) }
        return PronunciationResult(words: [WordScore(word: word, phonemes: scores)])
    }

    @Test
    func qualityBands() {
        #expect(ShadowingGOP.Quality.of(gop: -0.1) == .good)
        #expect(ShadowingGOP.Quality.of(gop: -0.3) == .good)
        #expect(ShadowingGOP.Quality.of(gop: -0.6) == .okay)
        #expect(ShadowingGOP.Quality.of(gop: -1.5) == .weak)
    }

    @Test
    func redToGreenIsImproved() {
        // /θ/ was weak in the target reference, native-clean in the attempt.
        let target = result("think", [("θ", -1.8), ("ɪ", -0.2), ("ŋ", -0.2), ("k", -0.2)])
        let attempt = result("think", [("θ", -0.1), ("ɪ", -0.2), ("ŋ", -0.2), ("k", -0.2)])
        let c = ShadowingGOP.compare(target: target, attempt: attempt)

        #expect(c.phonemes.count == 4)
        let th = c.phonemes.first { $0.symbol == "θ" }!
        #expect(th.verdict == .improved)
        #expect(th.targetQuality == .weak)
        #expect(th.attemptQuality == .good)
        #expect(th.delta > 0)
        #expect(c.improved.map(\.symbol) == ["θ"])
    }

    @Test
    func unchangedIsSame() {
        let target = result("cat", [("k", -0.2), ("æ", -0.3), ("t", -0.25)])
        let attempt = result("cat", [("k", -0.25), ("æ", -0.3), ("t", -0.2)])
        let c = ShadowingGOP.compare(target: target, attempt: attempt)
        #expect(c.phonemes.allSatisfy { $0.verdict == .same })
        #expect(c.improved.isEmpty)
        #expect(c.regressed.isEmpty)
    }

    @Test
    func regressionIsWorse() {
        let target = result("cat", [("k", -0.2), ("æ", -0.3)])
        let attempt = result("cat", [("k", -1.6), ("æ", -0.3)])
        let c = ShadowingGOP.compare(target: target, attempt: attempt)
        let k = c.phonemes.first { $0.symbol == "k" }!
        #expect(k.verdict == .worse)
        #expect(c.regressed.map(\.symbol) == ["k"])
    }

    @Test
    func betterWithinSameBand() {
        // Both "weak", but a clear improvement within the band.
        let target = result("the", [("ð", -2.5)])
        let attempt = result("the", [("ð", -1.4)])
        let c = ShadowingGOP.compare(target: target, attempt: attempt)
        let d = c.phonemes[0]
        #expect(d.verdict == .better)
        #expect(d.attemptQuality == .weak)
    }

    @Test
    func alignsAroundInsertedPhonemeInAttempt() {
        // Attempt inserted a stray schwa; the rest should still pair up by symbol.
        let target = result("dog", [("d", -0.2), ("ɔ", -0.3), ("ɡ", -0.2)])
        let attempt = result("dog", [("d", -0.2), ("ə", -2.0), ("ɔ", -0.3), ("ɡ", -0.2)])
        let c = ShadowingGOP.compare(target: target, attempt: attempt)
        #expect(c.phonemes.map(\.symbol) == ["d", "ɔ", "ɡ"])
        #expect(c.phonemes.allSatisfy { $0.verdict == .same })
    }

    @Test
    func stillWeakSurfacesRemainingWork() {
        let target = result("three", [("θ", -2.0), ("ɹ", -0.3), ("iː", -0.2)])
        let attempt = result("three", [("θ", -1.4), ("ɹ", -0.3), ("iː", -0.2)])
        let c = ShadowingGOP.compare(target: target, attempt: attempt)
        #expect(c.stillWeak.map(\.symbol) == ["θ"])
    }

    @Test
    func emptyInputsAreEmpty() {
        let c = ShadowingGOP.compare(target: PronunciationResult(words: []),
                                     attempt: PronunciationResult(words: []))
        #expect(c.isEmpty)
    }
}
