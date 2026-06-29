# [MC-3] macOS adopts the shared SwiftData store + JSON migration

- **Phase:** 1 — Unify model + sync
- **Depends on:** MC-1
- **Blocks:** MC-5, MC-7
- **Size:** L
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §2, §3

## Goal
Retire macOS's flat-JSON, local-only history in favor of the shared SwiftData store so Mac
history persists in the synced schema.

## Tasks
- [ ] Replace `HistoryFeature`'s `FileStorageKey<TranscriptionHistory>` with the shared SwiftData
      store from VocoEngine (read/write `TranscriptEntry`).
- [ ] One-time migration: read `transcription_history.json` → insert each as
      `TranscriptEntry(kind: .dictation)` into SwiftData; mark migrated; keep a backup of the JSON.
- [ ] Make migration idempotent (safe to run twice; dedupe on `id`).
- [ ] Keep the TCA transcription/paste pipeline writing through the new store.

## Acceptance criteria
- [ ] Existing Mac history appears intact after upgrade (nothing dropped).
- [ ] New Mac dictations persist as `TranscriptEntry` and survive relaunch.
- [ ] `xcodebuild build -scheme VocoMac` succeeds; macOS history tests green.

## Files
- `VocoMac/Features/History/HistoryFeature.swift`, `VocoMac/Features/Transcription/TranscriptionFeature.swift`
