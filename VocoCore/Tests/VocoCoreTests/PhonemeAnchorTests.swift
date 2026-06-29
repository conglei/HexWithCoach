import XCTest
@testable import VocoCore

final class PhonemeAnchorTests: XCTestCase {
    /// Coverage can't silently rot: every IPA symbol the GOP pipeline can emit
    /// (`PhonemeG2P.producibleSymbols`) must map to a non-empty exemplar + tip.
    func testCoversEveryProducibleSymbol() {
        for symbol in PhonemeG2P.producibleSymbols {
            guard let entry = PhonemeAnchor.guide(for: symbol) else {
                XCTFail("No PhonemeAnchor entry for producible symbol /\(symbol)/")
                continue
            }
            XCTAssertFalse(entry.exemplar.isEmpty, "Empty exemplar for /\(symbol)/")
            XCTAssertFalse(entry.tip.isEmpty, "Empty tip for /\(symbol)/")
        }
    }

    /// Sanity check the inventory is the size we expect (39 mapped phones + schwa).
    func testInventorySize() {
        XCTAssertEqual(PhonemeG2P.producibleSymbols.count, 40)
    }

    func testKnownSymbol() {
        let entry = PhonemeAnchor.guide(for: "ɑ")
        XCTAssertEqual(entry?.exemplar, "rob")
        XCTAssertFalse(entry?.tip.isEmpty ?? true)
    }

    func testUnknownSymbolReturnsNil() {
        XCTAssertNil(PhonemeAnchor.guide(for: "ʔ"))   // glottal stop, not in inventory
        XCTAssertNil(PhonemeAnchor.guide(for: ""))
        XCTAssertNil(PhonemeAnchor.guide(for: "xyz"))
    }

    func testSubstitutionTextMapped() {
        XCTAssertEqual(
            PhonemeAnchor.substitutionText(said: "oʊ", aim: "ɑ"),
            "you said /oʊ/ (as in \"robe\") — aim for /ɑ/ (as in \"rob\")"
        )
    }

    func testSubstitutionTextFallsBackForUnmapped() {
        // Unmapped "said" symbol → bare IPA; mapped "aim" still annotated.
        XCTAssertEqual(
            PhonemeAnchor.substitutionText(said: "ʔ", aim: "ɑ"),
            "you said /ʔ/ — aim for /ɑ/ (as in \"rob\")"
        )
        // Both unmapped → both bare.
        XCTAssertEqual(
            PhonemeAnchor.substitutionText(said: "ʔ", aim: "ʕ"),
            "you said /ʔ/ — aim for /ʕ/"
        )
    }
}
