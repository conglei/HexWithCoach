---
"hex-app": minor
---

Coach foundation (CE-1): bring the Gemini provider transport into the shared HexEngine layer and add iOS BYOK + opt-in. A new content-agnostic `GeminiClient` (Foundation-only, streaming + non-streaming, token usage for cost surfacing) and a shared `CoachKeychain` are now usable from both macOS and iOS instead of hand-rolling per platform or pulling in the deprecated google-generative-ai-swift / heavyweight Firebase AI SDK. On iOS, Settings gains a Coach section: off by default, opt-in toggle, paste-your-own Gemini API key (stored in the device Keychain, never synced), and a clear disclosure that turning the Coach on uploads dictations (text + audio) to Google's Gemini API. No analysis runs yet — that's the next step (CE-2/CE-3).
