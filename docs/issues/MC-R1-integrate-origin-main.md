# [MC-R1] Integrate origin/main (re-found base)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ◐ re-found, not rebase
- **Depends on:** upstream DM-2 + PR-1 merged to `origin/main`
- **Blocks:** MC-R2 (everything)
- **Size:** L
- **Design:** [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §2, §7

## Goal
Re-base the macOS Companion epic on top of `origin/main` (after the schema-defining Phase-3 tasks
land), adopting main's versions of the conflicting files and re-applying only the still-valid
macOS-only deltas.

## Tasks
- [ ] `git fetch`; confirm DM-2 (CoachObservation) + PR-1 (PracticeItem) are on `origin/main`.
- [ ] Start a fresh integration branch off `origin/main`.
- [ ] Re-apply macOS-only deltas that don't conflict: VocoMac window shell (MC-R0/MC-7), entitlements
      (MC-2), legacy-coach removal (MC-6) — adapted to main's current files.
- [ ] **Adopt main's** `TranscriptEntry`/`TranscriptAnalysis`/`CoachService`/`HistoryView`; do NOT
      reintroduce the old inline-blob schema.
- [ ] iOS target builds unchanged; macOS builds against the new model (stubs ok until MC-R2/R3).

## Acceptance criteria
- [ ] Branch builds on the new model; iOS behavior identical to `origin/main`.
- [ ] No duplicate/old `TranscriptEntry` definition remains.
