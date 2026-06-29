# [HS-5] History list: layout polish + day-header fix

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** —
- **Size:** M
- **Design:** [ios-ui-design-v1.md](../ios-ui-design-v1.md); this session

## Goal
The History tab (`Voco/Views/HistoryView.swift`, built across HS-1/HS-2/HS-3) is functional but
the layout needs polish. On device only ~5 notes are visible, the two stacked filter rows
(Notes/Dictation segment + date-scope chips) eat vertical space before any content shows, the
coach-insight badge is weak/ambiguous, and the day-section header appears to float in the wrong
place relative to its notes. Tighten density, streamline the filter header, make day headers
sticky and correctly placed, and clarify the coach badge — **without regressing** any HS-1/2/3
behavior.

## Tasks
- [ ] **Density:** tighten card padding and inter-card spacing so more notes are scannable while
      rows stay comfortably tappable (reduce `hexCard` padding, shrink row insets / day-header
      insets).
- [ ] **Filter header:** keep BOTH the Notes/Dictation segment AND the `This week / This month /
      All` scope chips, but shrink their combined vertical footprint (tighter padding; chips on the
      same compact band).
- [ ] **Day-header placement/order:** extract the day-grouping + sort into a pure helper and unit
      test it (within-day reverse-chronological, day sections newest-first, header above its notes).
      Render day headers as **sticky/pinned** section headers (`.listStyle(.plain)` pins headers;
      ensure custom insets don't break pinning) so they sit above their notes while scrolling.
- [ ] **Coach badge:** replace the weak `✦ N` with a clearer, legible pill affordance (icon +
      count) for processed notes that have insights; keep the pending (hourglass) and
      analyzed-no-insights (check) states. Row still opens `TranscriptDetailView`.
- [ ] **General polish:** consistent spacing, clear timestamp/kind hierarchy, sensible placement of
      the "Select" affordance.

## Acceptance criteria
- [ ] Noticeably denser list (more notes visible per screen) with comfortably tappable rows.
- [ ] Segment + scope chips occupy a single tight band; both remain fully functional.
- [ ] Within each day, notes are reverse-chronological and the day header sits ABOVE its notes;
      headers stay pinned while scrolling. Day-grouping helper has unit coverage.
- [ ] Coach badge is a clear, legible pill; rows still navigate to detail.
- [ ] No HS-1/2/3 regression: Notes/Dictation segment, windowed/bounded parameterized `@Query`,
      date-scope chips, "Load older", search-across-all-scopes, swipe-to-delete, multi-select bulk
      delete (+ cascade), coach-status badges, and navigation to detail all still work.
