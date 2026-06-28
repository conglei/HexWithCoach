import XCTest
@testable import HexCore

final class TeachingContentTests: XCTestCase {
    private var content: TeachingContent!

    override func setUpWithError() throws {
        content = try TeachingContent.load()
    }

    // MARK: - Decoding

    func testLoadsAllThreeAssets() throws {
        XCTAssertEqual(content.phonemeGuide.language, "en")
        XCTAssertGreaterThanOrEqual(content.phonemeGuide.version, 1)
        XCTAssertFalse(content.fluencyTips.tips.isEmpty)
        XCTAssertFalse(content.l1Interference.languages.isEmpty)
    }

    func testDefaultInstanceLoads() {
        // Exercising `.default` confirms the bundled assets are valid at runtime.
        XCTAssertFalse(TeachingContent.default.phonemeGuide.phonemes.isEmpty)
    }

    // MARK: - Phoneme guide

    func testPhonemeGuideHasAround40Phonemes() {
        let count = content.phonemeGuide.phonemes.count
        XCTAssertGreaterThanOrEqual(count, 38, "Expected ~40 English phonemes, got \(count)")
        XCTAssertLessThanOrEqual(count, 48, "Expected ~40 English phonemes, got \(count)")
    }

    func testPhonemeIPASymbolsAreUnique() {
        let ipas = content.phonemeGuide.phonemes.map(\.ipa)
        XCTAssertEqual(ipas.count, Set(ipas).count, "Duplicate IPA symbols in phoneme guide")
    }

    func testEveryPhonemeEntryIsPopulated() throws {
        for entry in content.phonemeGuide.phonemes {
            XCTAssertFalse(entry.ipa.isEmpty)
            XCTAssertFalse(entry.exampleWord.isEmpty, "empty exampleWord for \(entry.ipa)")
            XCTAssertFalse(entry.description.isEmpty, "empty description for \(entry.ipa)")
            XCTAssertFalse(entry.howToArticulate.isEmpty, "empty howToArticulate for \(entry.ipa)")
            XCTAssertFalse(entry.practiceSentence.isEmpty, "empty practiceSentence for \(entry.ipa)")
            XCTAssertFalse(entry.minimalPair.isEmpty, "empty minimalPair for \(entry.ipa)")
        }
    }

    func testPhonemeIPASymbolsAreInModelVocab() {
        // Every guide IPA must come from the eSpeak-IPA inventory the GOP model emits.
        for ipa in content.phonemeGuide.phonemes.map(\.ipa) {
            XCTAssertTrue(
                Self.modelVocab.contains(ipa),
                "Phoneme '\(ipa)' is not in the model's eSpeak-IPA vocab"
            )
        }
    }

    func testCoversCoreEnglishPhonemes() {
        // A spot-check of distinctive English sounds that must be present.
        for ipa in ["θ", "ð", "ɹ", "ŋ", "iː", "ɪ", "æ", "ə", "ɚ", "eɪ", "aɪ", "oʊ"] {
            XCTAssertNotNil(content.phoneme(ipa), "missing core phoneme \(ipa)")
        }
    }

    func testPhonemeLookup() throws {
        let th = try XCTUnwrap(content.phoneme("θ"))
        XCTAssertEqual(th.ipa, "θ")
        XCTAssertEqual(th.exampleWord, "think")
        XCTAssertFalse(th.commonL1Substitutions.isEmpty)
    }

    func testPhonemeLookupMissReturnsNil() {
        XCTAssertNil(content.phoneme("zzz-not-a-phoneme"))
    }

    // MARK: - Fluency tips

    func testFluencyTipsCoverEveryDimension() throws {
        for dimension in FluencyDimension.allCases {
            let tip = try XCTUnwrap(content.tip(for: dimension), "missing tip for \(dimension)")
            XCTAssertEqual(tip.dimension, dimension)
            XCTAssertFalse(tip.title.isEmpty)
            XCTAssertFalse(tip.tip.isEmpty)
        }
    }

    // MARK: - L1 interference

    func testL1TableCoversExpectedLanguages() throws {
        let expected = [
            "Mandarin", "Spanish", "Hindi", "Arabic", "Korean",
            "Japanese", "French", "German", "Portuguese", "Russian",
        ]
        for l1 in expected {
            let entry = try XCTUnwrap(content.interference(forL1: l1), "missing L1 \(l1)")
            XCTAssertFalse(entry.interferencePhonemes.isEmpty)
            XCTAssertFalse(entry.note.isEmpty)
        }
    }

    func testL1LookupIsCaseInsensitive() throws {
        let lower = try XCTUnwrap(content.interference(forL1: "mandarin"))
        let upper = try XCTUnwrap(content.interference(forL1: "MANDARIN"))
        XCTAssertEqual(lower, upper)
        XCTAssertEqual(lower.l1, "Mandarin")
    }

    func testL1LookupMissReturnsNil() {
        XCTAssertNil(content.interference(forL1: "Klingon"))
    }

    func testL1InterferencePhonemesAreInGuide() {
        // Every interference phoneme should have a guide entry so cards can teach it.
        let guideIPAs = Set(content.phonemeGuide.phonemes.map(\.ipa))
        for lang in content.l1Interference.languages {
            for ipa in lang.interferencePhonemes where Self.modelVocab.contains(ipa) {
                XCTAssertTrue(
                    guideIPAs.contains(ipa),
                    "\(lang.l1) interference phoneme '\(ipa)' has no guide entry"
                )
            }
        }
    }

    // MARK: - Fixtures

    /// The English subset of the model's eSpeak-IPA vocab the guide draws from.
    /// (Full inventory: tools/pronunciation-assets/phoneme_vocab.json.)
    private static let modelVocab: Set<String> = [
        "p", "b", "t", "d", "k", "ɡ", "tʃ", "dʒ", "f", "v", "θ", "ð", "s", "z",
        "ʃ", "ʒ", "h", "m", "n", "ŋ", "l", "ɹ", "w", "j",
        "iː", "ɪ", "ɛ", "æ", "ʌ", "ɑː", "ɔː", "ʊ", "uː", "ə", "ɚ", "ɜː",
        "eɪ", "aɪ", "ɔɪ", "aʊ", "oʊ",
    ]
}
