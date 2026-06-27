import Foundation

/// Which model tier a pipeline stage wants. The provider adapter maps these to
/// concrete models (deep-design §6: cheap model for extraction, stronger for the
/// critic). Kept provider-agnostic so the pipeline never names a vendor model.
public enum CoachModelTier: String, Sendable {
    case extract   // bulk per-lens candidate extraction (cheaper, audio-capable)
    case critic    // verification / synthesis (stronger)
}

/// Inline audio for the multimodal lens (CE-4 §4: feed transcript **and** audio;
/// we stop withholding the transcript).
public struct CoachAudio: Sendable, Equatable {
    public var data: Data
    public var mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Provider-agnostic LLM seam for the Coach pipeline. The concrete adapter
/// (e.g. `GeminiCoachLLM` in HexEngine) lives outside HexCore so the pipeline —
/// prompts, parsing, orchestration — stays unit-testable with a mock.
public protocol CoachLLM: Sendable {
    /// Returns the model's raw text response (expected to be a JSON object).
    func generateJSON(
        systemPrompt: String,
        userPrompt: String,
        audio: CoachAudio?,
        tier: CoachModelTier
    ) async throws -> String
}
