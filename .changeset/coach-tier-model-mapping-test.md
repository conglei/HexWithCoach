---
"hex-app": patch
---

Testing: cover the Coach's Gemini model-tiering logic. The tier→model decision (`.extract` → flash-lite, `.critic` → flash) moves out of the HexEngine `GeminiCoachLLM` adapter into a unit-tested `CoachModelTier.defaultGeminiModel` in HexCore, so `swift test` covers it directly. (A test bundle can't link the HexEngine adapter, and statically linking HexCore into a test bundle hits a SwiftPM transitive-link gap with ConcurrencyExtras — so the right move, consistent with the project's approach, is to keep testable logic in HexCore rather than fight the linker.) The adapter is now thin plumbing over the already-tested `GeminiClient` + this mapping.
