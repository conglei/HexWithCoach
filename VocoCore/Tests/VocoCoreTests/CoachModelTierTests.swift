import Testing
@testable import VocoCore

struct CoachModelTierTests {
    // Both tiers run on the stronger `flash` model: quality is the binding
    // constraint at our volume, and extraction is the audio-grounded pass where
    // the cheaper model hurt most.
    @Test
    func extractUsesStrongerModel() {
        #expect(CoachModelTier.extract.defaultGeminiModel == "gemini-3.5-flash")
    }

    @Test
    func criticUsesStrongerModel() {
        #expect(CoachModelTier.critic.defaultGeminiModel == "gemini-3.5-flash")
    }
}
