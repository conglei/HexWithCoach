import XCTest
@testable import VocoCore

final class WaveformEnvelopeTests: XCTestCase {
    func testReturnsRequestedBarCount() {
        let samples = (0 ..< 1000).map { Float(sin(Double($0) * 0.1)) }
        XCTAssertEqual(WaveformEnvelope.bars(from: samples, count: 40).count, 40)
    }

    func testPeakNormalizedToOne() {
        let samples = (0 ..< 1000).map { Float(sin(Double($0) * 0.1)) }
        let bars = WaveformEnvelope.bars(from: samples, count: 20)
        XCTAssertEqual(bars.max() ?? 0, 1.0, accuracy: 1e-5)
        XCTAssertTrue(bars.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testLouderSliceProducesTallerBar() {
        // First half quiet, second half loud → later bars should dominate.
        var samples = [Float](repeating: 0.05, count: 500)
        samples += [Float](repeating: 0.9, count: 500)
        let bars = WaveformEnvelope.bars(from: samples, count: 10)
        XCTAssertLessThan(bars[0], bars[9])
        XCTAssertEqual(bars[9], 1.0, accuracy: 1e-5)
    }

    func testSilenceYieldsFlatZeroStrip() {
        let bars = WaveformEnvelope.bars(from: [Float](repeating: 0, count: 800), count: 16)
        XCTAssertEqual(bars.count, 16)
        XCTAssertTrue(bars.allSatisfy { $0 == 0 })
    }

    func testFewerSamplesThanBarsYieldsZeroStrip() {
        let bars = WaveformEnvelope.bars(from: [0.5, 0.5, 0.5], count: 40)
        XCTAssertEqual(bars, Array(repeating: 0, count: 40))
    }

    func testZeroBarCountIsEmpty() {
        XCTAssertTrue(WaveformEnvelope.bars(from: [0.1, 0.2], count: 0).isEmpty)
    }
}
