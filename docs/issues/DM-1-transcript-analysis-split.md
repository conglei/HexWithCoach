# [DM-1] Split TranscriptEntry into a lean row + heavy analysis sidecar

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** —
- **Blocks:** DM-2, HS-2, HS-3
- **Size:** M
- **Design:** [transcript-analysis-split-plan.md](../transcript-analysis-split-plan.md)

## Goal
Keep the History list and corpus analytics cheap as note count grows by moving the bulky
per-note JSON (word timings, full pronunciation result) off the list-bearing row into a
lazily-faulted sidecar, keeping only a compact pronunciation summary on the row.

## Tasks
- [ ] Add `TranscriptAnalysis` `@Model` (`wordTimingsJSON`, `pronunciationJSON`, inverse
      `entry`); register it in **every** `ModelContainer(for:)` — `TranscriptStore.makeContainer`
      and the in-memory containers in `ContentView`, `OnboardingView`, `VocoTests`.
- [ ] Add `@Relationship(deleteRule: .cascade, inverse: \TranscriptAnalysis.entry) var analysis`
      to `TranscriptEntry`; add `pronunciationSummaryJSON` (compact `PronunciationSignals`, ~1 KB).
- [ ] Re-point the `wordTimings` / `pronunciationResult` accessors to the sidecar
      (create-on-write via `ensureAnalysis()`); keep `pronunciationSignals` reading the on-row
      summary; refresh the summary whenever `pronunciationResult` is set.
- [ ] Add `#Index` on `date` and `kindRaw`.
- [ ] Confirm readers compile unchanged (`CoachService` analysis path, `TranscriptDetailView`).

## Acceptance criteria
- [ ] Fetching entries for the History list / `ProgressDigestView` corpus scan does **not** fault
      `analysis` (verify in Instruments).
- [ ] `pronunciationResult` / `wordTimings` round-trip through the sidecar; `pronunciationSignals`
      reads the on-row summary.
- [ ] Greenfield: no migration/backfill code.
