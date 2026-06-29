# [MC-13] Opt-in audio sync (CloudKit external storage)

- **Phase:** 4 — Shadowing + audio sync
- **Depends on:** MC-2, MC-3
- **Blocks:** —
- **Size:** M
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §2, §5
- **Risk:** Medium — CKAsset size + initial-sync cost; needs device verification.

## Goal
Make recorded audio available across devices (for cross-device playback + pronunciation/shadowing
review), gated behind an opt-in toggle.

## Tasks
- [ ] Add `@Attribute(.externalStorage) var audioData: Data?` to `TranscriptEntry`; SwiftData stores
      out-of-row and CloudKit syncs it as a CKAsset.
- [ ] Ingest flow: recorder/keyboard temp file → host writes bytes into `audioData`; keep the local
      file path for fast playback.
- [ ] Opt-in toggle in Settings (both platforms), **off by default**; when off, audio stays local
      and only text/coach JSON syncs.
- [ ] Handle large clips gracefully (size guard; don't block the note save on asset upload).

## Acceptance criteria
- [ ] With the toggle on, audio recorded on one device plays back on the other (device verified).
- [ ] With the toggle off, no audio leaves the device; coach results still sync.
- [ ] Both apps build; no regression to text sync.

## Notes
- **Flag for owner device test** (CloudKit assets). Coexists with the App Group audio dir used by
  the keyboard; reconcile local-file vs synced-bytes ownership.

## Files
- `VocoEngine/SyncModels.swift`, capture/ingest paths, Settings (both platforms)
