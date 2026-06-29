# [MC-6] Remove the legacy macOS one-shot Coach

- **Phase:** 2 — macOS Coach v2
- **Depends on:** MC-5
- **Blocks:** —
- **Size:** M
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §3

## Goal
Delete the superseded stateless pronunciation path now that the v2 engine drives macOS.

## Tasks
- [ ] Remove `VocoMac/Features/Coach/*` (CoachFeature, CoachModels, CoachFeedbackStore,
      CoachPopoverView, CoachSettingsView) and `VocoMac/Clients/` Coach pieces
      (CoachClient, CoachNotifier, PronunciationProvider, Providers/Gemini+OpenAI).
- [ ] Detach from `AppFeature`; remove dead settings keys; clean dependency registrations.
- [ ] Re-point the menu-bar Coach affordance to "latest insight → open Review window" (or drop it).

## Acceptance criteria
- [ ] App builds and runs with no references to the removed types.
- [ ] No orphaned settings/menu items; `xcodebuild build -scheme VocoMac` succeeds.

## Files
- `VocoMac/Features/Coach/`, `VocoMac/Clients/CoachClient.swift`, `VocoMac/Clients/Providers/`
