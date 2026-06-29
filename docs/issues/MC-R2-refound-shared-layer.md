# [MC-R2] Re-found MC-1's shared layer on the Phase-3 model (NEW LINCHPIN)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ✅ this IS MC-1, brought back (mechanism intact; model body swapped)
- **Depends on:** MC-R1
- **Blocks:** MC-R3, MC-R4, MC-R5, MC-R7, MC-R8
- **Size:** L
- **Design:** [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §4, §6;
  [transcript-analysis-split-plan.md](../transcript-analysis-split-plan.md)

## Goal
Bring back MC-1's mechanism — shared `@Model` types + `SyncStore.makeContainer()` + `SyncPreferences`
in `VocoEngine`, synced via the one CloudKit container — now wrapping main's Phase-3 model so **both**
apps compile one synced schema.

## Carries forward (verbatim where possible)
- MC-2: shared CloudKit container + both entitlements + explicit `.private(cloudContainerID)` pin.
- MC-4: `LearnerProfileEntity` / `CoachSnapshotEntity` + `ProfileSyncStore` (re-express as
  observation-log projections where DM-2 makes that natural).
- The `duration` / `sourceAppBundleID` additive fields.

## Tasks
- [ ] Move main's `TranscriptEntry` (lean) + `TranscriptAnalysis` (sidecar) + `CoachObservation` (log)
      + `PracticeItem` into `VocoEngine` (synchronized folder → both targets compile them).
- [ ] Re-create `SyncStore.makeContainer()` registering ALL of the above; restore the CloudKit pin +
      local/in-memory fallbacks. Point iOS `TranscriptStore` + macOS store at it.
- [ ] Keep main's accessors (`wordTimings`/`pronunciationResult` → sidecar; `pronunciationSignals` →
      on-row summary) intact across the move.
- [ ] iOS in-memory/test containers + macOS containers register the same types.

## Acceptance criteria
- [ ] One schema in `VocoEngine`; iOS + macOS both compile it; `cd VocoCore && swift test` green.
- [ ] iOS behavior unchanged (lean row + sidecar + observation log as on `origin/main`).
- [ ] Records sync via the single CloudKit container (live merge = device-verify, see MC-2).
