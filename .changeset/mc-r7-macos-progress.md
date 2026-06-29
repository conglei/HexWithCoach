---
"hex-app": patch
---

Add the macOS Progress digest to the Coach hub (MC-R7): a never-punishing streak, per-lens levels and trends, a weekly digest, mastered-pattern wins, and per-word pronunciation (GOP) trends. Per-lens and per-word trends are queried from the synced `CoachObservation` log and rendered with Swift Charts; streak/levels/wins reuse the shared progress types. Read-only — never writes coach state.
