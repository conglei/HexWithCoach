# [MC-11] macOS History as search over the synced store

- **Phase:** 3 — Companion window
- **Depends on:** MC-7
- **Blocks:** —
- **Size:** S
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §3

## Goal
Reframe macOS History as a searchable browse surface over the synced `TranscriptEntry` store
(dictation + notes together), matching the iOS demotion of History to search.

## Tasks
- [ ] History section: `@Query` list with search, filter by `kind`, detail view (text + audio + context).
- [ ] Copy / delete; play audio from the record.
- [ ] Replace the old Settings-window History tab usage where the main window now covers it.

## Acceptance criteria
- [ ] Search returns matching transcripts/notes across synced entries.
- [ ] `xcodebuild build -scheme VocoMac` succeeds.

## Files
- `VocoMac/Views/` History views
