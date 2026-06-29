# [MC-10] macOS Progress digest

- **Phase:** 3 — Companion window
- **Depends on:** MC-5, MC-7
- **Blocks:** —
- **Size:** M
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §3

## Goal
Show growth on the Mac: per-lens deltas, streak, mastered patterns — reusing the shared
`ProgressSummary` / `CoachProgress`.

## Tasks
- [ ] Progress section: weekly digest (per-lens deltas e.g. Fillers 5.1→3.2 ↓38%), never-punishing
      streak, mastered-pattern wins — driven by the synced profile + snapshots.
- [ ] Native Mac layout (Swift Charts where it fits); reuse `CoachProgress.summary()`.

## Acceptance criteria
- [ ] Digest reflects the synced profile (consistent with iOS for the same account).
- [ ] `xcodebuild build -scheme VocoMac` succeeds.

## Files
- `VocoMac/Views/` Progress views
