import XCTest
@testable import VocoCore

final class L1InterferencePriorTests: XCTestCase {
    private var content: TeachingContent!

    override func setUpWithError() throws {
        content = try TeachingContent.load()
    }

    // MARK: - Known L1 → expected phonemes

    func testKnownL1ReturnsItsInterferencePhonemes() throws {
        let entry = try XCTUnwrap(content.interference(forL1: "Mandarin"))
        let prioritized = L1InterferencePrior.prioritizedPhonemes(forL1: "Mandarin", content: content)
        // Mandarin's interference phonemes all have guide entries, so the prior
        // returns them in table order.
        XCTAssertEqual(prioritized, entry.interferencePhonemes)
        XCTAssertTrue(prioritized.contains("θ"))
        XCTAssertTrue(prioritized.contains("ɹ"))
    }

    func testLookupIsCaseInsensitive() {
        let lower = L1InterferencePrior.prioritizedPhonemes(forL1: "spanish", content: content)
        let upper = L1InterferencePrior.prioritizedPhonemes(forL1: "SPANISH", content: content)
        XCTAssertEqual(lower, upper)
        XCTAssertFalse(lower.isEmpty)
    }

    func testEveryPrioritizedPhonemeHasAGuideEntry() {
        for lang in content.l1Interference.languages {
            let prioritized = L1InterferencePrior.prioritizedPhonemes(forL1: lang.l1, content: content)
            for ipa in prioritized {
                XCTAssertNotNil(content.phoneme(ipa), "\(lang.l1) prior phoneme \(ipa) has no guide entry")
            }
        }
    }

    func testResultHasNoDuplicates() {
        for lang in content.l1Interference.languages {
            let prioritized = L1InterferencePrior.prioritizedPhonemes(forL1: lang.l1, content: content)
            XCTAssertEqual(prioritized.count, Set(prioritized).count, "duplicates for \(lang.l1)")
        }
    }

    // MARK: - Unknown / nil L1 → empty

    func testUnknownL1ReturnsEmpty() {
        XCTAssertTrue(L1InterferencePrior.prioritizedPhonemes(forL1: "Klingon", content: content).isEmpty)
    }

    func testNilL1ReturnsEmpty() {
        XCTAssertTrue(L1InterferencePrior.prioritizedPhonemes(forL1: nil, content: content).isEmpty)
    }

    func testBlankL1ReturnsEmpty() {
        XCTAssertTrue(L1InterferencePrior.prioritizedPhonemes(forL1: "   ", content: content).isEmpty)
    }
}
