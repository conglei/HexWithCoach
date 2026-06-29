import Foundation
import Testing
@testable import HexCore

#if canImport(CoreML) && canImport(AVFoundation)
/// Tests for decoding the actually-pronounced sound from the emission matrix —
/// the mode of per-frame argmax (excluding blank) over a phoneme's aligned span.
/// Pure / model-free.
struct DominantClassTests {
    // emissions[frame][class]; class 0 = blank here.
    @Test func picksMostFrequentNonBlankArgmax() {
        let e: [[Float]] = [
            [0.1, 0.2, 0.7, 0.0], // argmax 2
            [0.1, 0.2, 0.6, 0.1], // argmax 2
            [0.1, 0.7, 0.1, 0.1], // argmax 1
            [0.9, 0.0, 0.0, 0.1], // argmax 0 (blank) → ignored
        ]
        #expect(PronunciationAnalyzer.dominantClass(in: e, frames: 0 ..< 4, blank: 0) == 2)
    }

    @Test func returnsNilWhenAllBlankDominated() {
        let e: [[Float]] = [[0.9, 0.1], [0.8, 0.2]]
        #expect(PronunciationAnalyzer.dominantClass(in: e, frames: 0 ..< 2, blank: 0) == nil)
    }

    @Test func skipsOutOfRangeFrames() {
        let e: [[Float]] = [[0.1, 0.9], [0.1, 0.9]]
        #expect(PronunciationAnalyzer.dominantClass(in: e, frames: 0 ..< 10, blank: 0) == 1)
    }

    @Test func tieBreaksTowardSmallerClassId() {
        // class 1 and class 3 each dominate one frame → tie → smaller id wins.
        let e: [[Float]] = [
            [0.0, 0.9, 0.0, 0.1],
            [0.0, 0.1, 0.0, 0.9],
        ]
        #expect(PronunciationAnalyzer.dominantClass(in: e, frames: 0 ..< 2, blank: 0) == 1)
    }
}
#endif
