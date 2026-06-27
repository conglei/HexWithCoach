//
//  GeminiCoachLLM.swift
//  HexEngine (shared: macOS Hex + iOS HexIOS)
//
//  Adapts the shared `GeminiClient` transport to the pipeline's provider-agnostic
//  `CoachLLM` seam (defined in HexCore). The pipeline — prompts, parsing,
//  orchestration — stays vendor-neutral and unit-testable; this is the one place
//  that knows the concrete Gemini models per tier.
//

import Foundation
import HexCore

struct GeminiCoachLLM: CoachLLM {
    let apiKey: String
    private let client: GeminiClient

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.client = GeminiClient(session: session)
    }

    func generateJSON(
        systemPrompt: String,
        userPrompt: String,
        audio: CoachAudio?,
        tier: CoachModelTier
    ) async throws -> String {
        // Tier the models (deep-design §6): cheap, audio-capable model for bulk
        // extraction; the stronger model for verification/synthesis. The mapping
        // is a unit-tested HexCore function so it doesn't rely on this adapter
        // being reachable from a test bundle.
        let model = tier.defaultGeminiModel

        var parts: [GeminiPart] = [.text(userPrompt)]
        if let audio {
            parts.append(.inlineData(mimeType: audio.mimeType, data: audio.data))
        }

        let result = try await client.generate(
            model: model,
            apiKey: apiKey,
            parts: parts,
            systemInstruction: systemPrompt,
            temperature: 0.2,
            jsonResponse: true
        )
        return result.text
    }
}
