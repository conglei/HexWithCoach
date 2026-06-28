# [RC-0] Substrate prereqs: audio retention + dictations persisted as `Transcript`

- **Phase:** 2 — Review/Coach companion
- **Depends on:** — (verify against `main`)
- **Blocks:** RC-2, RC-8
- **Size:** S
- **Design:** [review-coach-companion-design.md](../review-coach-companion-design.md) §13

## Goal
Guarantee the corpus the Coach mines actually exists: every dictation (cross-app + notes) is
persisted with audio retained.

## Tasks
- [ ] Confirm iOS **retains audio** (the prototype `DictationModel` historically `removeItem`'d it).
      Audio is required for pronunciation/fluency coaching, "play what you said", and shadowing.
- [ ] Confirm keyboard/Flow-Session dictations persist as `Transcript(kind: .dictation,
      sourceAppName: <host app>)` — not just in-app notes.
- [ ] Confirm `Transcript.kind` enum exists (unified-history-data-model §2.2); add if missing.
- [ ] Confirm portable audio identity (filename, not absolute path) per data-model §4.

## Acceptance criteria
- [ ] A cross-app dictation and an in-app note both appear in `TranscriptStore` with retained audio.
- [ ] `kind` distinguishes them; source app captured for dictations.
