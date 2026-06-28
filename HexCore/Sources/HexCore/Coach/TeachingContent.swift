import Foundation

// MARK: - Models

/// One bundled phoneme entry from the static **phoneme guide** — the keyless
/// teaching reference that powers deterministic pronunciation cards (CI-4,
/// ADR-0002). Authored once, versioned, and enriched per-learner by the LLM
/// only when a key is present. IPA symbols match the model's eSpeak-IPA
/// inventory (`tools/pronunciation-assets/phoneme_vocab.json`).
public struct PhonemeGuideEntry: Codable, Equatable, Sendable {
    /// The eSpeak-IPA symbol, used as the stable lookup key.
    public let ipa: String
    /// A short English word that contains the phoneme.
    public let exampleWord: String
    /// One-sentence plain-language description of the sound.
    public let description: String
    /// One-sentence, mouth-level instruction for producing the sound.
    public let howToArticulate: String
    /// IPA symbols learners commonly substitute for this phoneme (L1-driven).
    public let commonL1Substitutions: [String]
    /// A friendly sentence loaded with the target phoneme for practice.
    public let practiceSentence: String
    /// A `target / contrast` minimal pair that isolates the phoneme.
    public let minimalPair: String

    public init(
        ipa: String,
        exampleWord: String,
        description: String,
        howToArticulate: String,
        commonL1Substitutions: [String],
        practiceSentence: String,
        minimalPair: String
    ) {
        self.ipa = ipa
        self.exampleWord = exampleWord
        self.description = description
        self.howToArticulate = howToArticulate
        self.commonL1Substitutions = commonL1Substitutions
        self.practiceSentence = practiceSentence
        self.minimalPair = minimalPair
    }
}

/// The decoded phoneme guide asset (`phoneme_guide.json`).
public struct PhonemeGuide: Codable, Equatable, Sendable {
    public let version: Int
    public let language: String
    public let phonemes: [PhonemeGuideEntry]

    public init(version: Int, language: String, phonemes: [PhonemeGuideEntry]) {
        self.version = version
        self.language = language
        self.phonemes = phonemes
    }
}

/// The fluency dimension a tip addresses. Mirrors the objective fluency signals
/// (fillers / long pauses / restarts / pace) detected in `FluencySignals`.
public enum FluencyDimension: String, Codable, Equatable, Sendable, CaseIterable {
    case fillers
    case longPauses
    case restarts
    case pace
}

/// One actionable fluency tip from the bundled **fluency-tips table**.
public struct FluencyTip: Codable, Equatable, Sendable {
    public let dimension: FluencyDimension
    public let title: String
    public let tip: String

    public init(dimension: FluencyDimension, title: String, tip: String) {
        self.dimension = dimension
        self.title = title
        self.tip = tip
    }
}

/// The decoded fluency-tips asset (`fluency_tips.json`).
public struct FluencyTips: Codable, Equatable, Sendable {
    public let version: Int
    public let tips: [FluencyTip]

    public init(version: Int, tips: [FluencyTip]) {
        self.version = version
        self.tips = tips
    }
}

/// One first-language entry from the bundled **L1 → interference** table. The
/// keyless prioritization prior (ADR-0003): when the learner's L1 is known,
/// surface its typical English interference phonemes first.
public struct L1InterferenceEntry: Codable, Equatable, Sendable {
    /// Canonical L1 key (e.g. "Mandarin"), used for lookup.
    public let l1: String
    /// Human-facing language name.
    public let displayName: String
    /// eSpeak-IPA phonemes English learners with this L1 typically struggle with.
    public let interferencePhonemes: [String]
    /// One-sentence summary of why these sounds are hard for this L1.
    public let note: String

    public init(l1: String, displayName: String, interferencePhonemes: [String], note: String) {
        self.l1 = l1
        self.displayName = displayName
        self.interferencePhonemes = interferencePhonemes
        self.note = note
    }
}

/// The decoded L1-interference asset (`l1_interference.json`).
public struct L1InterferenceTable: Codable, Equatable, Sendable {
    public let version: Int
    public let languages: [L1InterferenceEntry]

    public init(version: Int, languages: [L1InterferenceEntry]) {
        self.version = version
        self.languages = languages
    }
}

// MARK: - Loader

/// Loads and indexes the bundled keyless teaching assets (phoneme guide,
/// fluency tips, L1 interference table) shipped as SwiftPM package resources.
///
/// Pure and synchronous: it decodes from `Bundle.module` once at init and
/// exposes O(1) lookups. The shared ``default`` instance is the normal entry
/// point; tests can construct one directly from decoded models.
public struct TeachingContent: Sendable {
    public let phonemeGuide: PhonemeGuide
    public let fluencyTips: FluencyTips
    public let l1Interference: L1InterferenceTable

    private let phonemesByIPA: [String: PhonemeGuideEntry]
    private let tipsByDimension: [FluencyDimension: FluencyTip]
    private let l1ByKey: [String: L1InterferenceEntry]

    public init(
        phonemeGuide: PhonemeGuide,
        fluencyTips: FluencyTips,
        l1Interference: L1InterferenceTable
    ) {
        self.phonemeGuide = phonemeGuide
        self.fluencyTips = fluencyTips
        self.l1Interference = l1Interference

        self.phonemesByIPA = Dictionary(
            phonemeGuide.phonemes.map { ($0.ipa, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.tipsByDimension = Dictionary(
            fluencyTips.tips.map { ($0.dimension, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.l1ByKey = Dictionary(
            l1Interference.languages.map { ($0.l1.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: Lookups

    /// The phoneme guide entry for an eSpeak-IPA symbol, or nil if not covered.
    public func phoneme(_ ipa: String) -> PhonemeGuideEntry? {
        phonemesByIPA[ipa]
    }

    /// The fluency tip for a dimension.
    public func tip(for dimension: FluencyDimension) -> FluencyTip? {
        tipsByDimension[dimension]
    }

    /// The interference entry for a learner's L1 (case-insensitive on the key).
    public func interference(forL1 l1: String) -> L1InterferenceEntry? {
        l1ByKey[l1.lowercased()]
    }

    // MARK: Loading

    /// Errors raised while loading the bundled teaching assets.
    public enum LoadError: Error, Equatable {
        case missingResource(String)
    }

    /// Decodes all three assets from the package's resource bundle.
    public static func load() throws -> TeachingContent {
        let guide: PhonemeGuide = try decode("phoneme_guide")
        let tips: FluencyTips = try decode("fluency_tips")
        let l1: L1InterferenceTable = try decode("l1_interference")
        return TeachingContent(phonemeGuide: guide, fluencyTips: tips, l1Interference: l1)
    }

    /// The shared, lazily-loaded instance over the bundled assets. Traps on a
    /// packaging error because the assets ship with the binary — a missing or
    /// malformed asset is a build-time mistake, not a runtime condition.
    public static let `default`: TeachingContent = {
        do {
            return try load()
        } catch {
            fatalError("Failed to load bundled teaching content: \(error)")
        }
    }()

    private static func decode<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw LoadError.missingResource(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
