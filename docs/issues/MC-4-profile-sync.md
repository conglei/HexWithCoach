# [MC-4] Sync LearnerProfile + growth history

- **Phase:** 1 — Unify model + sync
- **Depends on:** MC-1
- **Blocks:** MC-5
- **Size:** M
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §2

## Goal
The LearnerProfile is the moat; it should follow the user across devices. Today it is file-JSON
and not synced.

## Tasks
- [ ] Add `LearnerProfileEntity` + `CoachSnapshotEntity` SwiftData models in `VocoEngine`, wrapping
      the existing `Codable` `LearnerProfile` / `CoachSnapshotLog` payloads (single-row style).
- [ ] Migrate existing file-JSON profile/snapshots into the SwiftData records on first launch.
- [ ] Route `LearnerProfileStore` / `CoachSnapshotStore` reads/writes through the synced records.
- [ ] Confirm BYOK Keychain key stays **per-device** (unchanged — never synced).

## Acceptance criteria
- [ ] Profile + growth snapshots merge across Mac and iOS via CloudKit.
- [ ] Existing on-device profile is preserved after migration.
- [ ] `cd VocoCore && swift test` green (pure logic unchanged); both apps build.

## Files
- `VocoEngine/SyncModels.swift`, `VocoCore/Sources/VocoCore/Coach/LearnerProfile.swift` (callsites)
