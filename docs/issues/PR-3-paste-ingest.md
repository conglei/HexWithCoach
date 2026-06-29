# [PR-3] Paste-to-practice ingest → segment → shadowing

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** PR-1, PR-2
- **Blocks:** PR-4
- **Size:** M
- **Design:** this session (Practice); reuse RC-4 `ShadowingModel` (TTS → speak → ASR/GOP delta)

## Goal
Let users paste or type arbitrary text and practice it. Pasted text is just a new **source** for
the existing shadowing engine — no new scoring engine needed.

## Tasks
- [ ] Paste/type entry → create a `.pasted` `PracticeItem`.
- [ ] Segment the text into speakable sentences (with a segment preview).
- [ ] Feed each segment to `ShadowingModel`; score with the existing GOP/ASR + delta vs last attempt.
- [ ] Session-end summary; save attempts onto the `PracticeItem`.

## Acceptance criteria
- [ ] Pasted text becomes a practiced item with per-segment scores and improvement deltas.
- [ ] Nothing is written to History / `TranscriptStore`.
