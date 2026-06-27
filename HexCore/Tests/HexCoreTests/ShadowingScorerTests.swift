import Testing
@testable import HexCore

/// TDD for RC-4: how closely the user's repeat matched the target phrase.
struct ShadowingScorerTests {
    @Test
    func identicalIsPerfect() {
        #expect(ShadowingScorer.match(target: "went to the store", spoken: "went to the store") == 1.0)
    }

    @Test
    func ignoresCaseAndPunctuation() {
        let s = ShadowingScorer.match(target: "I'd love to, honestly.", spoken: "id love to honestly")
        #expect(s == 1.0)
    }

    @Test
    func emptySpokenIsZero() {
        #expect(ShadowingScorer.match(target: "hello there", spoken: "") == 0.0)
    }

    @Test
    func oneWordOffInFourIsThreeQuarters() {
        // "went to a store" vs "went to the store" — one substitution of 4 words.
        let s = ShadowingScorer.match(target: "went to the store", spoken: "went to a store")
        #expect(abs(s - 0.75) < 0.0001)
    }

    @Test
    func unrelatedIsLow() {
        let s = ShadowingScorer.match(target: "let's circle back tomorrow", spoken: "the cat sat down")
        #expect(s < 0.3)
    }

    @Test
    func isMatchUsesThreshold() {
        #expect(ShadowingScorer.isMatch(target: "went to the store", spoken: "went to the store"))
        #expect(!ShadowingScorer.isMatch(target: "went to the store", spoken: "completely different words here"))
    }
}
