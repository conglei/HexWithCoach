# [CE-1] Coach engine foundation + provider transport in HexCore + iOS BYOK

- **Phase:** 2 — Coach engine (deep)
- **Depends on:** — (replaces the old RC-1 "port")
- **Blocks:** CE-2, CE-3, CE-4, CE-5
- **Size:** L
- **Design:** [coach-engine-deep-design.md](../coach-engine-deep-design.md) §7

## Goal
The shared, provider-agnostic foundation the deep pipeline builds on — reusing only the plumbing,
discarding the shallow one-shot prompt.

## Tasks
- [ ] Move the **reusable plumbing** into HexCore: Gemini HTTP/SSE transport + JSON extraction
      (generalize into a `ProviderTransport`), `CoachFeedbackEntry`/`CoachFeedbackHistory`
      persistence, `@Shared(.coachFeedback)` key. (`CoachSettings`, `KeychainClient` already shared.)
- [ ] Define a **provider-agnostic** engine interface that takes `Transcript.text` **+ audio +
      word timings + LearnerProfile** (not the old one-shot `PronunciationInput`).
- [ ] **Model tiering** config: cheap-extract / strong-critic+synthesis / audio-capable lens.
- [ ] iOS **BYOK** (Keychain) + opt-in + cloud-upload disclosure. Gemini only (OpenAI stub stays).
- [ ] Keep the thin TCA `CoachClient` wrapper per app target (HexCore stays TCA-free).
- [ ] **Discard** the one-shot `defaultPromptTemplate` + single-pass `CoachMarkdownParser` flow.

## Acceptance criteria
- [ ] HexCore exposes a provider-agnostic engine; macOS + iOS both build against it.
- [ ] An analysis call can receive transcript + audio + profile and return per-lens structured output.
