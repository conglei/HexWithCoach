# [PR-1] PracticeItem model + store

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** —
- **Blocks:** PR-2, PR-3
- **Size:** S
- **Design:** this session (Practice)

## Goal
Model practice items as their own type, **separate from `TranscriptEntry`** — pasted / coach /
phrasebook targets are not captures and must never appear in History.

## Tasks
- [ ] `PracticeItem` model: `target` text, `segments: [String]`, `origin`
      (`.coachInsight(id)` / `.phrasebook` / `.pasted`), `createdAt`, `attempts: [Attempt]`.
- [ ] `Attempt`: `date`, per-segment scores, GOP delta (reuse the `ShadowingModel` scoring shape).
- [ ] Its own store — **not** in `TranscriptStore`. Recommend a SwiftData `@Model` (synced), kept
      out of every History `@Query`.

## Acceptance criteria
- [ ] Practice items persist and never surface in History queries.
