# [MC-R5] macOS Coach hub — Review feed + activation (was MC-8)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ◐/➕ re-cut MC-7 `MacReviewView` → `MacCoachView`; new IA
- **Depends on:** MC-R0, MC-R4
- **Blocks:** MC-R6, MC-R9
- **Size:** L
- **Design:** [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §5;
  IA-1, IA-2 (Coach hub + activation)

## Goal
Build the macOS **Coach** hub: Review feed + activation, reading projections of the `CoachObservation`
log / `CoachCardEntity`. Mirror the iOS coach concepts from #81–#87.

## Tasks
- [ ] `MacCoachView` hub hosting the Review feed (cards/observations), with Progress (MC-R7) and
      Practice (MC-R6) sections under it per IA-1.
- [ ] Card actions: Say it better (→ Practice/Shadowing), Save, Got it / Not useful, play audio, in-context.
- [ ] Keyless-first + LLM upsell; activation bait + first-run nudge (IA-2), phrased for opt-in/paid.
- [ ] Reflect #81–#87: interactive pronunciation sounds, severity-ranked "sounds to work on",
      calm note view + selective coloring, "what an unclear sound came out as".

## Acceptance criteria
- [ ] Keyless user sees objective cards; actions persist; cards sync from iOS appear on macOS.
- [ ] `xcodebuild build -scheme VocoMac` succeeds.
