# [DM-2] CoachObservation log + curation/profile as projections

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** DM-1
- **Blocks:** CT-1, CT-2
- **Size:** L
- **Design:** [transcript-analysis-split-plan.md](../transcript-analysis-split-plan.md) (Tier 3 + Write sites)

## Goal
Persist every coaching finding as an append-only, dated `CoachObservation` so cross-note
coaching (frequency over time, regression, evidence trails, per-word GOP trends) becomes a
query. Today raw `CoachInsight`s are **discarded** at curation (`CoachService.swift:268-270`,
`:357-359`) — only one deduped card per pattern key survives.

## Reuse
`CoachCardCurator` and `LearnerProfile` updates stay, re-expressed as **projections** built
from the persisted observations rather than from transient insights.

## Tasks
- [ ] Add `CoachObservation` `@Model` (`id`, `noteID`, `date`, `lensRaw`, `originRaw`,
      `patternKey?`, `word?`, `gop?`, `severity`, `span?`) + `Origin` enum (`objective | llm`);
      register in all containers.
- [ ] Add `recordObservations(_:for:origin:)` helper in `CoachService`.
- [ ] LLM lane: persist `analysis.insights` at `analyzeTranscript` (~268) and per-entry inside the
      `analyzeBacklog` loop (~337), `origin: .llm`, **before** curation.
- [ ] Objective lane: emit per-word pronunciation observations in `analyzePronunciation` (~389),
      `origin: .objective`, with `word` + `gop`.
- [ ] `date` = note capture date (trends bucket by speaking day). Log `span` with `, privacy: .private`.
- [ ] Coordinate the delete path: clear observations by `noteID` (see HS-3).

## Acceptance criteria
- [ ] An analysis run appends one observation per finding with correct `noteID`/`date`/`lens`/`origin`.
- [ ] A per-word pronunciation query returns dated GOPs for a word across multiple notes.
- [ ] Curated cards and profile behavior are unchanged, now derived from the observation log.
