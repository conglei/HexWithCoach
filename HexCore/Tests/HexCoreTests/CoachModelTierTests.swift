import Testing
@testable import HexCore

struct CoachModelTierTests {
    @Test
    func extractUsesCheapAudioModel() {
        #expect(CoachModelTier.extract.defaultGeminiModel == "gemini-2.5-flash-lite")
    }

    @Test
    func criticUsesStrongerModel() {
        #expect(CoachModelTier.critic.defaultGeminiModel == "gemini-2.5-flash")
        // Guard against the flash / flash-lite substring trap.
        #expect(CoachModelTier.critic.defaultGeminiModel != CoachModelTier.extract.defaultGeminiModel)
    }
}
