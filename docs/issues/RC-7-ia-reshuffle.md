# [RC-7] IA reshuffle: Review home, History → search, capture off home

> **STATUS: SUPERSEDED by [IA-1](IA-1-tab-restructure-coach.md)** (Phase 3 — Notebook & Coach v2).
> The IA decided here is reversed: the app stays **capture-first** (Home is the front door),
> **History stays a primary tab**, and **Review + Practice merge** into a Coach tab (Home / History
> / Coach / Settings). The neighbor design RC-7 referenced is **not** lost — the Review feed (RC-3),
> card curation (RC-2), shadowing (RC-4), phrasebook (RC-5), and progress (RC-6) now live **inside**
> the Coach tab, and RC-7/§8's **activation model** (baited empty state + first-run nudge) is carried
> forward as **[IA-2](IA-2-coach-activation.md)**. Kept for the record of why. Do not implement as written.

- **Phase:** 2 — Review/Coach companion
- **Depends on:** RC-3
- **Blocks:** —
- **Size:** M
- **Design:** [review-coach-companion-design.md](../review-coach-companion-design.md) §4
- **Note:** This is the **delta to the locked [ios-ui-design-v1.md](../ios-ui-design-v1.md) IA.**
  Sequence deliberately; coordinate before editing the locked doc (other agents build against it).

## Goal
Shift the host app's front door from capture to **Review**, matching the companion model.

## Tasks
- [ ] Tabs: **Home/History/Settings → Review/Notes/Settings**.
- [ ] **Review** becomes the home tab (RC-3 feed + RC-6 header).
- [ ] **History demoted** to a "search / browse all my speech" screen reached from Review (no longer
      a primary tab); item detail (annotation) opens from feed or search (§12).
- [ ] **Remove capture from Home**; in-app note capture moves into the **Notes** tab; cross-app
      capture stays in the keyboard.
- [ ] Position **Notes** as a capture-and-release inbox (copy/share out; optional archive/done).
- [ ] Update the locked design doc IA section once landed (coordinated).

## Acceptance criteria
- [ ] App opens into Review; Notes and Settings are the other tabs; History is reachable via search.
- [ ] No capture mic on the home/front door.
