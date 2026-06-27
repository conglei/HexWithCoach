import Testing
@testable import HexCore

struct CoachModelTierTests {
    @Test
    func extractUsesCheapAudioModel() {
        #expect(CoachModelTier.extract.defaultGeminiModel == "gemini-3.1-flash-lite")
    }

    @Test
    func criticUsesStrongerModel() {
        #expect(CoachModelTier.critic.defaultGeminiModel == "gemini-3.1-flash")
        // Guard against the flash / flash-lite substring trap.
        #expect(CoachModelTier.critic.defaultGeminiModel != CoachModelTier.extract.defaultGeminiModel)
    }
}
