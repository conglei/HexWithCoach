import XCTest
@testable import VocoCore

final class GOPColoringTests: XCTestCase {
    func testGoodBucketAtAndAboveGoodCutoff() {
        XCTAssertEqual(GOPColoring.bucket(forGOP: 0.0), .good)
        XCTAssertEqual(GOPColoring.bucket(forGOP: GOPColoring.goodCutoff), .good)
        XCTAssertEqual(GOPColoring.bucket(forGOP: -0.1), .good)
    }

    func testFairBucketBetweenCutoffs() {
        // Just below the good cutoff is fair.
        XCTAssertEqual(GOPColoring.bucket(forGOP: GOPColoring.goodCutoff - 0.0001), .fair)
        XCTAssertEqual(GOPColoring.bucket(forGOP: -0.6), .fair)
        // Exactly at the fair cutoff is still fair (inclusive lower bound).
        XCTAssertEqual(GOPColoring.bucket(forGOP: GOPColoring.fairCutoff), .fair)
    }

    func testWeakBucketBelowFairCutoff() {
        XCTAssertEqual(GOPColoring.bucket(forGOP: GOPColoring.fairCutoff - 0.0001), .weak)
        XCTAssertEqual(GOPColoring.bucket(forGOP: -2.5), .weak)
    }

    func testNeutralForMissingGOP() {
        let none: Double? = nil
        XCTAssertEqual(GOPColoring.bucket(forGOP: none), .neutral)
    }

    func testOptionalForwardsToValue() {
        XCTAssertEqual(GOPColoring.bucket(forGOP: Double?.some(-0.05)), .good)
        XCTAssertEqual(GOPColoring.bucket(forGOP: Double?.some(-3.0)), .weak)
    }

    func testBucketOrderingIsWorseAsRawValueGrows() {
        XCTAssertLessThan(GOPColoring.Bucket.good.rawValue, GOPColoring.Bucket.fair.rawValue)
        XCTAssertLessThan(GOPColoring.Bucket.fair.rawValue, GOPColoring.Bucket.weak.rawValue)
    }

    func testDeterministicAcrossRepeatedCalls() {
        for gop in stride(from: 0.0, through: -3.0, by: -0.13) {
            XCTAssertEqual(GOPColoring.bucket(forGOP: gop), GOPColoring.bucket(forGOP: gop))
        }
    }
}
