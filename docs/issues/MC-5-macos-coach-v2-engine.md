# [MC-5] Wire the Coach v2 two-lane engine on macOS

- **Phase:** 2 — macOS Coach v2
- **Depends on:** MC-3, MC-4
- **Blocks:** MC-8, MC-10, MC-12
- **Size:** L
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §3

## Goal
Replace the macOS stateless one-shot popover Coach with the shared v2 pipeline (objective
always-on + LLM auto-batched), reusing VocoCore.

## Tasks
- [ ] Promote `CoachService`, `CoachPreferences`, `CoachProgress` (currently iOS-target
      `@Observable`) into `VocoEngine` now that they operate on shared models; both apps consume them.
- [ ] On macOS, run the objective lane at capture (GOP + fluency, idempotent via
      `objectiveAnalyzedAt`) and the LLM lane auto-batched under the budget cap (BYOK Gemini).
- [ ] Persist `CoachCardEntity` cards into the synced store.
- [ ] BYOK key entry + opt-in + budget surfaced in macOS Settings (reuse `CoachKeychain`).

## Acceptance criteria
- [ ] A new macOS dictation produces objective coach cards with no key; LLM cards when a key is set.
- [ ] `cd VocoCore && swift test` green; `xcodebuild build -scheme VocoMac` succeeds.
- [ ] No regression to iOS Coach (shared orchestrators still drive iOS).

## Files
- `VocoEngine/CoachService.swift` (moved), `VocoMac/` Settings + capture wiring
