# [MC-R8] macOS History — Notes|Dictation + windowed (was MC-11)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ◐ MC-11 aligned to HS-1/HS-2
- **Depends on:** MC-R3, MC-R0
- **Blocks:** —
- **Size:** S
- **Design:** HS-1, HS-2; [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §5

## Goal
macOS History as a segmented (Notes\|Dictation), windowed/paginated browse + search over the lean row.

## Tasks
- [ ] Notes\|Dictation segment (HS-1); default Notes; remember last selection.
- [ ] Date-scope chips + `fetchLimit` windowed fetch (HS-2); "Load older"; search across all scopes.
- [ ] Detail view faults the `TranscriptAnalysis` sidecar only on open; play audio; copy/delete (cascade).

## Acceptance criteria
- [ ] Bounded fetch (no full-table load); segments + search behave like the iOS HS-1/HS-2 surfaces.
- [ ] `xcodebuild build -scheme VocoMac` succeeds.
