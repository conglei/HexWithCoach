# [SR-2] Shadowing result: word-level pronunciation feedback

- **Phase:** 3 — Notebook & Coach v2 (Shadowing result)
- **Depends on:** SR-1
- **Blocks:** —
- **Size:** L
- **Design:** this session (Say-it-better redesign mockup)

## Goal
Redesign the shadowing **result** state (the screen shown after the user speaks, in
`Voco/Views/ShadowingView.swift`) so feedback is honest, word-level, and actionable — and add the
two missing affordances: hear your own recording, and retry.

## Problem with today's screen
- Says **"Nailed it!"** while listing 3 pronunciation errors — it conflates *did you say the right
  words* (ASR match) with *how native-like were the sounds* (GOP). These must be shown separately.
- A flat phoneme list loses **where** in the phrase the issues are.
- Raw IPA with no plain-English anchor.
- No **retry**, no way to **hear your own** recording.

## Tasks
- [ ] **Dual-signal verdict** (replace the misleading "Nailed it!"): a score + two distinct signals
      — **Right words** (ASR match) and **N sounds to polish** (GOP). Honest, calibrated headline
      ("Almost there — 3 sounds to polish"); lead with the win when there is one.
- [ ] **Word-level phrase**: render the target sentence word-by-word, each tinted by its per-word
      GOP (good / close / off). Derive per-word quality from `PronunciationResult` +
      `wordTimings`. Flagged words are underlined and **tappable to expand** their phoneme detail.
      Include a small good/close/off legend.
- [ ] **Focused issues list** using **SR-1's `PhonemeGuide`**: each issue = word + "you said /X/
      (as in …) — aim for /Y/ (as in …)" + the articulation tip. Order by severity, cap at top ~3.
      Keep bare IPA as fallback when a symbol is unmapped.
- [ ] **Compare playback**: keep "Hear native" (existing TTS) and add **"Hear yours"** — play back
      the user's recorded clip. (Per-word playback is a later nice-to-have, not required here.)
- [ ] **Audio retention**: persist/keep the recorded clip long enough for "Hear yours"
      (`ShadowingModel` currently may discard it after scoring — retain it for the result screen).
- [ ] **"Try again"** as the primary action (re-record the same target); show the improvement
      **delta vs the last attempt** when available (the closed-loop GOP comparison already exists).
      Keep "Done" secondary.
- [ ] Do NOT regress: existing single-shot callers (`ReviewView`, the coach drill in `PracticeView`,
      `TranscriptDetailView`, `SoundDetailSheet`) and the PR-3 paste session (the
      `dismissOnComplete` flag + `PasteSessionState`) must keep working. Still persist the
      `PracticeAttempt` exactly as PR-3 does.

## Tests
- [ ] Pure logic where extractable: per-word quality bucketing (GOP → good/close/off thresholds)
      and issue ordering/selection — unit-test in `VocoCore` (or `VocoTests`).
- [ ] Build green on the Voco scheme; existing shadowing tests still pass.

## Acceptance criteria
- [ ] The verdict never claims success while showing unresolved sound errors; ASR vs GOP are separate.
- [ ] The phrase shows per-word coloring; tapping a flagged word reveals its phoneme detail with a
      plain-English anchor + tip.
- [ ] The user can hear their own recording and the native version, and can retry in place.
