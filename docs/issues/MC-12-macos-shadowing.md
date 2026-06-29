# [MC-12] macOS Shadowing practice

- **Phase:** 4 — Shadowing + audio sync
- **Depends on:** MC-8
- **Blocks:** —
- **Size:** M
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §3, §4

## Goal
Closed-loop "say it better" on the Mac: hear the native rewrite → record your attempt → GOP
re-score, reusing the shared `ShadowingModel` / `ShadowingScorer`.

## Tasks
- [ ] Promote `ShadowingModel` into `VocoEngine` (shared) if not already; macOS Shadowing view.
- [ ] TTS the target phrase (AVSpeechSynthesizer), record attempt, ASR match, GOP re-score deltas
      when the phoneme model is present.
- [ ] Entry point from a Review card's "Say it better".

## Acceptance criteria
- [ ] Shadowing flow works on Mac (hear → record → result), with GOP deltas when model installed.
- [ ] `cd VocoCore && swift test` green; `xcodebuild build -scheme VocoMac` succeeds.

## Files
- `VocoEngine/ShadowingModel.swift` (moved), `VocoMac/Views/` Shadowing view
