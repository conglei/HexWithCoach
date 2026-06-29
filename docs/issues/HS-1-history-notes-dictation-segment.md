# [HS-1] History: separate Notes and Dictation

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** —
- **Blocks:** HS-2
- **Size:** S
- **Design:** this session (History redesign); [ios-ui-design-v1.md](../ios-ui-design-v1.md) (locked IA — coordinate)

## Goal
Split the mixed History list into a `Notes | Dictation` segment so intentional captures and
cross-app keyboard insertions read as distinct surfaces. Default to **Notes**.

## Tasks
- [ ] Segmented control at the top of `HistoryView` filtering on `kind` (`.note` / `.dictation`).
- [ ] Default = Notes; remember last selection.
- [ ] Per-segment empty states.

## Acceptance criteria
- [ ] Notes and Dictation are independently browsable; counts and empty states are correct per segment.
