import Testing
@testable import VocoCore

/// Verifies the CTC forced-alignment core on hand-built emission matrices where
/// the optimal alignment is unambiguous. Vocabulary: 0 = blank, 1 = "A", 2 = "B".
struct PhonemeAlignmentTests {
    private let blank = 0
    private let a = 1
    private let b = 2

    /// One-hot-ish logit row favoring class `c`.
    private func row(_ c: Int) -> [Float] {
        var r = [Float](repeating: 0, count: 3)
        r[c] = 8
        return r
    }

    @Test
    func alignsTwoPhonemesToTheirFrames() {
        let emissions = CTCForcedAligner.logSoftmax(rows: [row(a), row(a), row(b), row(b)])
        let spans = CTCForcedAligner.align(emissions: emissions, targets: [a, b], blank: blank, frameDuration: 0.02)
        #expect(spans != nil)
        guard let spans else { return }
        #expect(spans.count == 2)
        #expect(spans[0].label == a)
        #expect(abs(spans[0].start - 0.0) < 1e-6)
        #expect(abs(spans[0].end - 0.04) < 1e-6)
        #expect(spans[1].label == b)
        #expect(abs(spans[1].start - 0.04) < 1e-6)
        #expect(abs(spans[1].end - 0.08) < 1e-6)
        // Dominant class → GOP log-prob very close to 0.
        #expect(spans[0].logProb < 0)
        #expect(spans[0].logProb > -0.01)
    }

    @Test
    func skipsLeadingBlankBeforeFirstPhoneme() {
        let emissions = CTCForcedAligner.logSoftmax(rows: [row(blank), row(a), row(a), row(b)])
        let spans = CTCForcedAligner.align(emissions: emissions, targets: [a, b], blank: blank, frameDuration: 0.02)
        guard let spans else { Issue.record("alignment failed"); return }
        #expect(spans.count == 2)
        // First phoneme starts at frame 1 (frame 0 is blank).
        #expect(abs(spans[0].start - 0.02) < 1e-6)
        #expect(abs(spans[0].end - 0.06) < 1e-6)
        #expect(abs(spans[1].start - 0.06) < 1e-6)
        #expect(abs(spans[1].end - 0.08) < 1e-6)
    }

    @Test
    func repeatedPhonemeIsSeparatedByBlank() {
        // "A A" must place a blank between the two A's (standard CTC rule).
        let emissions = CTCForcedAligner.logSoftmax(rows: [row(a), row(blank), row(a)])
        let spans = CTCForcedAligner.align(emissions: emissions, targets: [a, a], blank: blank, frameDuration: 0.02)
        guard let spans else { Issue.record("alignment failed"); return }
        #expect(spans.count == 2)
        #expect(spans[0].label == a && spans[1].label == a)
        #expect(abs(spans[0].start - 0.0) < 1e-6)
        #expect(abs(spans[0].end - 0.02) < 1e-6)
        #expect(abs(spans[1].start - 0.04) < 1e-6)
        #expect(abs(spans[1].end - 0.06) < 1e-6)
    }

    @Test
    func returnsNilWhenFewerFramesThanPhonemes() {
        let emissions = CTCForcedAligner.logSoftmax(rows: [row(a)])
        let spans = CTCForcedAligner.align(emissions: emissions, targets: [a, b], blank: blank, frameDuration: 0.02)
        #expect(spans == nil)
    }

    @Test
    func lowerLogProbForPoorlyMatchedFrames() {
        // Frames weakly favor A (logit 1 vs 8) → GOP noticeably more negative.
        let weak: [[Float]] = [[0, 1, 0], [0, 1, 0]]
        let strong = CTCForcedAligner.logSoftmax(rows: [row(a), row(a)])
        let weakLog = CTCForcedAligner.logSoftmax(rows: weak)
        let weakSpan = CTCForcedAligner.align(emissions: weakLog, targets: [a], blank: blank, frameDuration: 0.02)
        let strongSpan = CTCForcedAligner.align(emissions: strong, targets: [a], blank: blank, frameDuration: 0.02)
        guard let weakSpan, let strongSpan else { Issue.record("alignment failed"); return }
        #expect(weakSpan[0].logProb < strongSpan[0].logProb)
    }
}
