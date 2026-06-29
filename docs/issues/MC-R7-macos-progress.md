# [MC-R7] macOS Progress — observation-log projections (was MC-10)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ◐ MC-10 re-pointed at the CoachObservation log
- **Depends on:** MC-R4, MC-R0
- **Blocks:** —
- **Size:** M
- **Design:** [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §4–§5

## Goal
macOS Progress digest under the Coach hub: per-lens deltas, streak, mastered patterns, per-word GOP
trends — now **queried from `CoachObservation`** (the durable substrate) rather than only curated cards.

## Tasks
- [ ] Per-lens trends + per-word pronunciation trends as queries over `CoachObservation` (dated rows).
- [ ] Never-punishing streak; mastered-pattern wins; weekly digest (reuse shared `ProgressSummary`).
- [ ] Native Mac layout (Swift Charts where it fits).

## Acceptance criteria
- [ ] Digest reflects the synced observation log (consistent with iOS for the same account).
- [ ] `xcodebuild build -scheme VocoMac` succeeds.
