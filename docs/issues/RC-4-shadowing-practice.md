# [RC-4] Shadowing practice (rephrase → TTS → repeat)

- **Phase:** 2 — Review/Coach companion
- **Depends on:** RC-3
- **Blocks:** —
- **Size:** M
- **Design:** [review-coach-companion-design.md](../review-coach-companion-design.md) §6

## Goal
Make a card actionable: hear the natural version, then say it back (active recall on your own
real sentence — the "drill" that isn't a random drill).

## Tasks
- [ ] "Say it better" flow: show the rephrase → **TTS speak it** (`AVSpeechSynthesizer`, on-device;
      neural-voice upgrade later) → record the user repeating it.
- [ ] On-device ASR confirms the user produced the phrase; optional cloud delivery/pronunciation
      check when Coach/BYOK is on.
- [ ] Practice counts toward streak/level (RC-6). Never a forced gate — reading the rewrite is
      valuable on its own.

## Acceptance criteria
- [ ] Tapping "Say it better" plays the rewrite and accepts a repeat with a clear success state.
- [ ] Works offline for the TTS + basic ASR confirmation path.
