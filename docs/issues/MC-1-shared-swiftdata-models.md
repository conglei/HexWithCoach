# [MC-1] Shared SwiftData models in VocoEngine

- **Phase:** 1 — Unify model + sync
- **Depends on:** —
- **Blocks:** MC-2, MC-3, MC-4, MC-5
- **Size:** L
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §2

## Goal
One note schema both apps compile, plus a shared CloudKit-backed container factory. This is
the linchpin — nothing else syncs or ports until it lands.

## Tasks
- [ ] Move `TranscriptEntry` + `CoachCardEntity` out of `Voco/TranscriptStore.swift` into the
      shared `VocoEngine/` folder (e.g. `VocoEngine/SyncModels.swift`), so both Voco (iOS) and
      VocoMac compile the identical `@Model` types.
- [ ] Add a shared `ModelContainer` factory in `VocoEngine` (e.g. `SyncStore.swift`) that builds
      the CloudKit-backed container and falls back to local-only when no iCloud account — the
      existing iOS logic, now reusable by both targets.
- [ ] Keep iOS `TranscriptStore` working by pointing it at the shared model + factory (no behavior
      change on iOS).
- [ ] Ensure VocoEngine remains UIKit/AppKit-free so it compiles into both app modules.

## Acceptance criteria
- [ ] `cd VocoCore && swift test` green.
- [ ] `xcodebuild build -scheme Voco` and `xcodebuild build -scheme VocoMac` both succeed.
- [ ] iOS history still loads/saves exactly as before (no schema change beyond the move).

## Files
- `VocoEngine/SyncModels.swift`, `VocoEngine/SyncStore.swift`, `Voco/TranscriptStore.swift`
