import Foundation
import Testing
@testable import VocoCore

#if canImport(CoreML) && canImport(AVFoundation)
/// Tests for detecting *syllabic realizations* of an expected phoneme — connected-speech
/// reductions the phoneme model has dedicated tokens for (`-ful` → [əl], `little` → [l̩]).
/// The forced aligner expects the un-merged phonemes, so the merged/syllabic token would
/// otherwise decode as a bogus substitution. Pure / model-free.
struct SyllabicRealizationTests {
    @Test func digraphMergeWithNext() {
        // "-ful": expected schwa /ə/ fuses with the following /l/ into the "əl" token.
        #expect(PronunciationAnalyzer.isSyllabicRealization(
            decoded: "əl", expected: "ə", prev: "f", next: "l") == true)
    }

    @Test func digraphMergeWithPrev() {
        // Same merged "əl" token, but aligned against the /l/ whose prev is the schwa.
        #expect(PronunciationAnalyzer.isSyllabicRealization(
            decoded: "əl", expected: "l", prev: "ə", next: nil) == true)
    }

    @Test func diacriticSyllabicConsonant() {
        // "little": syllabic [l̩] (l + U+0329) is the same /l/ as a syllable nucleus.
        #expect(PronunciationAnalyzer.isSyllabicRealization(
            decoded: "l\u{0329}", expected: "l", prev: nil, next: nil) == true)
    }

    @Test func genuineSubstitutionIsNotSyllabic() {
        // /m/ pronounced as /n/ is a real swapped sound, not a syllabic realization.
        #expect(PronunciationAnalyzer.isSyllabicRealization(
            decoded: "n", expected: "m", prev: nil, next: nil) == false)
    }

    @Test func identicalDecodedAndExpectedIsNotSyllabic() {
        #expect(PronunciationAnalyzer.isSyllabicRealization(
            decoded: "ə", expected: "ə", prev: nil, next: "l") == false)
    }

    @Test func unrelatedDigraphNotMatchingNeighboursIsNotSyllabic() {
        // "əl" decoded but neither neighbour is /l/ → not a merge of the expected phoneme.
        #expect(PronunciationAnalyzer.isSyllabicRealization(
            decoded: "əl", expected: "ə", prev: nil, next: "n") == false)
    }
}
#endif
