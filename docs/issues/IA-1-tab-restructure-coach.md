# [IA-1] Tab restructure: merge Review + Practice into "Coach"

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** —
- **Blocks:** PR-2
- **Size:** M
- **Design:** this session (holistic IA); [ios-ui-design-v1.md](../ios-ui-design-v1.md) (locked — update once landed)
- **Note:** **Supersedes the RC-7 plan.** RC-7 moved capture off Home and demoted History to
  search. New direction: Home **keeps** capture, History **stays** a primary tab (see HS-*), and
  **Review + Practice merge** into one Coach tab. Reconcile/close RC-7 when this lands.

## Goal
Land the four-tab structure **Home / History / Coach / Settings**. Coach merges the Review feed
and Practice into one learning hub (feedback cards + drills + paste + phrasebook + progress),
keeping the tab count at four without burying practice.

## Tasks
- [ ] Replace the Review tab with a **Coach** tab hosting the Review feed + Practice sections.
- [ ] Move Phrasebook and the Progress digest under Coach.
- [ ] Keep Home (capture + recents) and History (HS-*) as separate tabs.
- [ ] Update the locked `ios-ui-design-v1.md` IA section (coordinated).

## Relocated from RC-7 (superseded)
The coaching surfaces RC-7 wanted as the **front door** now live **inside** the Coach tab; the
front door is unchanged (Home stays capture-first):
- Review feed + activation shell (RC-3), card curation (RC-2), shadowing (RC-4), phrasebook (RC-5),
  progress/digest (RC-6) — all hosted under Coach.
- Activation bait + first-run nudge → tracked separately as **IA-2** (capture-first means the
  coaching hero is no longer the first screen, so activation needs an explicit nudge).

## Acceptance criteria
- [ ] Four tabs: Home / History / Coach / Settings.
- [ ] Coach surfaces both feedback and practice without a fifth tab.
