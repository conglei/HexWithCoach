# [MC-R3] macOS store on the lean row + windowed fetch (re-do MC-3)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ◐ MC-3 store-bridge pattern re-applied on the lean row + HS-1/HS-2
- **Depends on:** MC-R2
- **Blocks:** MC-R8
- **Size:** M
- **Design:** [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §4–§5

## Goal
Re-apply MC-3's macOS store bridge against the new lean `TranscriptEntry` + sidecar, and align macOS
history reads to HS-1 (Notes\|Dictation) + HS-2 (windowed/paginated) instead of the old full-table mirror.

## Tasks
- [ ] macOS store reads/writes the lean row; heavy artifacts go through the faulted `TranscriptAnalysis`
      sidecar (never faulted by list/corpus scans).
- [ ] Windowed fetch (date-scope chips + `fetchLimit`) per HS-2; Notes\|Dictation segment per HS-1.
- [ ] No JSON→SwiftData migration (greenfield; main dropped it). Remove MC-3's migration path.
- [ ] Dictation capture writes through the new store; coach hooks (MC-R4) fire after save.

## Acceptance criteria
- [ ] macOS History lists Notes\|Dictation over a bounded window; detail faults the sidecar only on demand.
- [ ] `xcodebuild build -scheme VocoMac` succeeds.
