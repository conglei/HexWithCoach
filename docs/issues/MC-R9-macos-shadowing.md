# [MC-R9] macOS Shadowing (was MC-12)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ◐ MC-12 over the shared PracticeItem/ShadowingModel
- **Depends on:** MC-R5, MC-R6
- **Blocks:** —
- **Size:** M
- **Design:** RC-4 (shadowing); [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §6

## Goal
Closed-loop "say it better" on macOS: hear native rewrite → record attempt → GOP re-score, recording
attempts on the shared `PracticeItem` (synced) and reusing `ShadowingModel`/`ShadowingScorer`.

## Tasks
- [ ] macOS Shadowing view: TTS target → record → ASR match → GOP deltas when phoneme model present.
- [ ] Persist attempts on `PracticeItem`; entry from a Coach card's "Say it better".

## Acceptance criteria
- [ ] Shadowing works on Mac (hear → record → result) with GOP deltas when the model is installed.
- [ ] `cd VocoCore && swift test` green; `xcodebuild build -scheme VocoMac` succeeds.
