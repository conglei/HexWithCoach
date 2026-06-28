# [RC-7] IA reshuffle: Review home, History → search, capture off home

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
