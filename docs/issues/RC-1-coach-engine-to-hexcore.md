# [RC-1] ~~Port Coach engine to HexCore~~ — SUPERSEDED

> **SUPERSEDED (2026-06-26).** The existing engine is too superficial to be the product's engine, so
> "port it" is the wrong plan. It is **replaced** by a deep, corpus-stateful pipeline.
> See **[coach-engine-deep-design.md](../coach-engine-deep-design.md)** and the **CE-1..CE-5** task
> series. CE-1 covers the plumbing extraction + iOS BYOK that this task originally scoped.

- **Status:** SUPERSEDED by [CE-1](CE-1-engine-foundation.md)..[CE-5](CE-5-cadence-cost-control.md)

---

_Original scope (kept for history):_

## Goal
Run the existing Coach on iOS where the speech is captured, by sharing its engine in HexCore.

## Already shared (no work)
- `CoachSettings` is already in HexCore; `KeychainClient` is cross-platform.

## Tasks
- [ ] Move the **TCA-free core** into HexCore: `Feedback`/`Issue`/`CoachFeedbackEntry`/
      `CoachFeedbackHistory` (from `Hex/Features/Coach/CoachModels.swift`), `PronunciationProvider`
      + `PronunciationInput/Output`, the **Gemini provider** (live) and OpenAI stub, and a plain
      `CoachEngine` (the `analyze`/`analyzeStream` logic currently in `CoachClient.liveValue`).
- [ ] Keep the thin TCA `CoachClient` (`@DependencyClient`) wrapper **in each app target** so
      HexCore needn't depend on ComposableArchitecture.
- [ ] Confirm the `@Shared(.coachFeedback)` persistence key + history are reachable on iOS
      (move the key def into HexCore if needed).
- [ ] iOS **BYOK**: API key in Keychain, opt-in flow, cloud-upload disclosure naming the provider.
      Default **off**. (Note: only **Gemini** is implemented; OpenAI remains a stub.)
- [ ] Keep `customPromptTemplate` escape hatch + `rawMarkdown`/`isStructured` fallback + streaming.
- [ ] coach-v2 5-perspective schema is **additive/later** (C1) — V1 ships on the existing `Feedback`.

## Acceptance criteria
- [ ] iOS can analyze a `Transcript` via a user-provided key and store `CoachFeedbackEntry`
      (FK `transcriptID`); streaming works.
- [ ] macOS Coach still builds/behaves unchanged over the shared core.
