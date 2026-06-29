# [HS-2] History: windowed fetch + date-scope chips (pagination)

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** DM-1 (lean row), HS-1
- **Blocks:** —
- **Size:** M
- **Design:** [transcript-analysis-split-plan.md](../transcript-analysis-split-plan.md) (Problem / History scaling); this session

## Goal
Replace the unbounded `@Query(sort: \.date)` (loads every row, `HistoryView.swift:18`) with a
bounded, windowed fetch. Date-scope chips (`This week` / `This month` / `All`) double as
pagination — they bound the predicate + `fetchLimit`. Default to **This week**.

## Tasks
- [ ] Date-scope chips bounding a `FetchDescriptor` predicate (`date >= scopeStart`) + `fetchLimit` (~50).
- [ ] "Load older" extends the window.
- [ ] Search runs as its own bounded fetch across **all** scopes (not trapped in the active range).
- [ ] Grouping/sectioning operates only on the loaded window.
- [ ] Rely on the `#Index` on `date`/`kindRaw` from DM-1.

## Acceptance criteria
- [ ] With thousands of seeded notes, opening History materializes only the window (Instruments:
      bounded memory, no full-table load).
- [ ] Date scopes + "Load older" reach the full history; search finds older items regardless of scope.
