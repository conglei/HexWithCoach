---
"hex-app": patch
---

Testing: move the `GeminiClient` transport from the app-shared `HexEngine/` folder into HexCore so it's directly covered by `swift test`, and add 7 tests for it (stubbed `URLSession`, no network) covering request URL/body building, system-instruction + inline-audio parts, JSON-mode, token-usage parsing, SSE streaming deltas, non-2xx errors, and the missing-key guard. Documents the three test runners in CLAUDE.md (HexCore `swift test`; the `HexTests` macOS bundle; the `HexIOSTests` iOS bundle) and the rule that `swift test` only covers HexCore — `HexEngine/` and app code must be tested through the Xcode test bundles. The `GeminiCoachLLM` adapter stays in HexEngine and now consumes the public client.
