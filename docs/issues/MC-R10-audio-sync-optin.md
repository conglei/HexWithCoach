# [MC-R10] Opt-in audio sync (was MC-13)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ◐ MC-13 unchanged in intent; lands on the new sidecar model
- **Depends on:** MC-R2, MC-R3
- **Blocks:** —
- **Size:** M
- **Risk:** Medium — CKAsset size + initial-sync cost; **device-verify**.
- **Design:** [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §6;
  original [macos-companion-v1-design.md](../macos-companion-v1-design.md) §2

## Goal
Sync recorded audio across devices (cross-device playback + pronunciation/shadowing review), opt-in,
off by default. Land it on the lean-row + sidecar model (likely an `@Attribute(.externalStorage)`
on the sidecar, so it never weighs down the list-bearing row).

## Tasks
- [ ] `@Attribute(.externalStorage) var audioData: Data?` on `TranscriptAnalysis` (sidecar) → CKAsset.
- [ ] Ingest temp file bytes into the sidecar; keep local path for fast playback.
- [ ] Opt-in Settings toggle (both platforms), default OFF; when off, audio stays local, text/coach syncs.
- [ ] Size guard; don't block note save on asset upload.

## Acceptance criteria
- [ ] Toggle ON: audio recorded on one device plays on the other (device-verified).
- [ ] Toggle OFF: no audio leaves the device; coach results still sync.

## Notes
- **Flag for owner device test** (CloudKit assets). Reconcile with the App-Group audio dir.
