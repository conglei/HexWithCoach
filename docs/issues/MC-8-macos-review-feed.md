# [MC-8] macOS Review feed

- **Phase:** 3 — Companion window
- **Depends on:** MC-5, MC-7
- **Blocks:** MC-12
- **Size:** L
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §3

## Goal
The hero surface on Mac: a feed of learnable-moment cards over the synced store.

## Tasks
- [ ] Review section: card list (`@Query` `CoachCardEntity`) — context / you-said / more-natural /
      why / lens, native Mac layout (hover, keyboard nav, multi-column where it helps).
- [ ] Card actions: Say it better (→ MC-12), Save, Got it / Not useful, play audio, see in context.
- [ ] Keyless-first: objective cards show without a key; LLM upsell banner when no key.
- [ ] Streak/progress header stub (full surface in MC-10).

## Acceptance criteria
- [ ] Keyless user sees objective cards; card actions update state and persist.
- [ ] Cards created on iOS appear in the Mac feed (via sync) and vice versa.
- [ ] `xcodebuild build -scheme VocoMac` succeeds.

## Files
- `VocoMac/Views/` Review views
