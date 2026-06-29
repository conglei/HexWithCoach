# [HS-3] History: delete (swipe + multi-select) with cascade

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** DM-1 (cascade sidecar), DM-2 (observation cleanup)
- **Blocks:** —
- **Size:** M
- **Design:** [transcript-analysis-split-plan.md](../transcript-analysis-split-plan.md) (Deletion); this session

## Goal
Add deletion (currently unsupported anywhere — `HistoryView` is read-only). Deleting a note must
cascade to all its satellites so no orphaned files or ghost cards remain.

## Tasks
- [ ] Swipe-to-delete on a row, with confirm (notes carry coaching history).
- [ ] "Select" mode in the header for multi-select bulk delete (incl. a "clear dictation history" sweep).
- [ ] Cascade per deleted note:
  - `modelContext.delete(entry)` (sidecar removed via `.cascade`)
  - remove the audio file (`AudioStore` via `audioFilename`)
  - `CoachCardEntity` where `transcriptID == id`
  - `CoachObservation` where `noteID == id`
  - the `CoachSnapshot` for the note

## Acceptance criteria
- [ ] After delete: no orphaned audio file, no cards/observations/snapshot for that `id`, no row.
- [ ] Bulk delete removes all selected notes and their satellites.
