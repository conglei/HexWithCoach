# [MC-9] macOS Notebook capture

- **Phase:** 3 — Companion window
- **Depends on:** MC-7
- **Blocks:** —
- **Size:** M
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §3

## Goal
Record-a-thought capture on the Mac that saves into the app (never pastes elsewhere), matching
the iOS Notebook job.

## Tasks
- [ ] Notebook section: "New note" → record → on-device transcribe → save as
      `TranscriptEntry(kind: .note)` in the synced store.
- [ ] List of notes (transcript-first, searchable), play audio, delete.
- [ ] Feed notes into the coach corpus like iOS (objective lane runs at capture).

## Acceptance criteria
- [ ] A note recorded on Mac saves locally, survives relaunch, and syncs to iOS.
- [ ] Notes are distinguishable from dictation by `kind`.
- [ ] `xcodebuild build -scheme VocoMac` succeeds.

## Files
- `VocoMac/Views/` Notebook views, capture wiring
