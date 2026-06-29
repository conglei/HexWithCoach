import Foundation
import Testing
@testable import VocoCore

/// Behavior spec for `CoachSettings` — its defaults, the `thresholdSec` clamp, and
/// its deliberately tolerant `Codable` decoding.
///
/// Written against intended behavior, not the implementation:
///   • Product invariant: the Coach is OFF by default, and the only v1 provider is
///     Gemini, so an unspecified provider should resolve to `.gemini`.
///   • `thresholdSec` is a user-facing "ignore clips shorter than N seconds" knob;
///     it must always land in a sane range so a corrupt/extreme persisted value
///     can never produce a nonsensical threshold.
///   • Settings must survive schema drift: decoding partial, empty, or
///     legacy-shaped JSON must succeed with defaults rather than throwing, so a
///     user never loses all settings because one field changed.
@Suite struct CoachSettingsTests {

    // MARK: Defaults

    @Test func defaultsMatchProductIntent() {
        let s = CoachSettings()
        #expect(s.enabled == false)            // Coach is opt-in / off by default.
        #expect(s.provider == .gemini)         // BYOK Gemini is the v1 provider.
        #expect(s.deleteAudioAfterAnalysis == false)
        #expect(s.autoShowPopover == true)
        #expect(s.customPromptTemplate == nil)
        #expect((3...120).contains(s.thresholdSec))
    }

    // MARK: thresholdSec clamping (invariant: always within [3, 120])

    @Test(arguments: [
        (input: 10, expected: 10),     // typical value preserved
        (input: 45, expected: 45),
        (input: 3, expected: 3),       // lower bound preserved
        (input: 120, expected: 120),   // upper bound preserved
        (input: 2, expected: 3),       // just below → clamped up
        (input: 0, expected: 3),       // zero → clamped up
        (input: -100, expected: 3),    // negative → clamped up
        (input: 121, expected: 120),   // just above → clamped down
        (input: 10_000, expected: 120) // far above → clamped down
    ])
    func thresholdIsClampedToUsableRange(input: Int, expected: Int) {
        #expect(CoachSettings(thresholdSec: input).thresholdSec == expected)
    }

    @Test func thresholdInvariantHoldsForArbitraryInputs() {
        for v in stride(from: -500, through: 500, by: 7) {
            let clamped = CoachSettings(thresholdSec: v).thresholdSec
            #expect((3...120).contains(clamped))
        }
    }

    // MARK: Round-trip encode → decode is lossless

    @Test func roundTripPreservesAllFields() throws {
        let originals = [
            CoachSettings(),
            CoachSettings(enabled: true, provider: .openai, thresholdSec: 45,
                          deleteAudioAfterAnalysis: true, autoShowPopover: false,
                          customPromptTemplate: "Be concise."),
            CoachSettings(enabled: true, provider: .gemini, thresholdSec: 7,
                          customPromptTemplate: nil)
        ]
        for original in originals {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(CoachSettings.self, from: data)
            #expect(decoded == original)
        }
    }

    // MARK: Tolerant decoding

    private func decode(_ json: String) throws -> CoachSettings {
        try JSONDecoder().decode(CoachSettings.self, from: Data(json.utf8))
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        let s = try decode("{}")
        #expect(s == CoachSettings())
    }

    @Test func partialObjectFillsMissingFieldsWithDefaults() throws {
        let s = try decode(#"{ "enabled": true }"#)
        #expect(s.enabled == true)
        #expect(s.provider == .gemini)
        #expect(s.autoShowPopover == true)
        #expect(s.customPromptTemplate == nil)
    }

    @Test func legacyUnknownKeysAreIgnored() throws {
        // Older builds persisted l1Language / targetAccent / userGoal / customGuidance.
        let s = try decode(#"""
        {
          "enabled": true,
          "l1Language": "es",
          "targetAccent": "us",
          "userGoal": "fluency",
          "customGuidance": "old field"
        }
        """#)
        #expect(s.enabled == true)
        #expect(s.provider == .gemini)
    }

    @Test func wronglyTypedFieldFallsBackToDefault() throws {
        // A settings load must never fail because one field has the wrong type.
        let s = try decode(#"{ "enabled": "yes please", "thresholdSec": "soon" }"#)
        #expect(s.enabled == false)              // bad Bool → default
        #expect((3...120).contains(s.thresholdSec))
    }

    @Test func unknownProviderFallsBackToGemini() throws {
        let s = try decode(#"{ "provider": "anthropic" }"#)
        #expect(s.provider == .gemini)
    }

    @Test func persistedOutOfRangeThresholdIsClampedOnDecode() throws {
        #expect(try decode(#"{ "thresholdSec": 1 }"#).thresholdSec == 3)
        #expect(try decode(#"{ "thresholdSec": 9999 }"#).thresholdSec == 120)
    }
}
