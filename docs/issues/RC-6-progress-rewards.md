# [RC-6] Progress & rewards

- **Phase:** 2 — Review/Coach companion
- **Depends on:** CE-2, CE-3
- **Blocks:** —
- **Size:** L
- **Design:** [review-coach-companion-design.md](../review-coach-companion-design.md) §7; [coach-v2-design.md](../coach-v2-design.md) §4 (longitudinal)

## Goal
Reward consistency and measurable improvement — without any score that can drop.

## Delta from macOS
macOS leads with a per-session `overallScore` /10 (red/orange/green, can drop). On iOS that score
stays only in **item detail** — it is **not** the headline. The headline is streak/deltas/wins/level.

## Tasks
- [ ] **Streak**: days with ≥1 review/shadow. Never punishing.
- [ ] **Per-lens deltas**: trends vs. the user's past self (e.g. fillers/min), from the
      longitudinal `CoachDigest` (coach-v2 §4.2).
- [ ] **Milestone wins**: collectible achievements ("mastered articles", "100 phrases shadowed",
      "filler rate −30% this month").
- [ ] **Only-up level** (optional anchor): XP from practice/streak; never decreases.
- [ ] **Surfacing**: Review-feed header (streak + one trend) → expands to a **weekly digest**
      (patterns + progress + next focus).

## Acceptance criteria
- [ ] Header shows streak + a real trend; digest shows per-lens deltas, wins, and a focus.
- [ ] No surfaced metric can decrease in a way that reads as a downgrade.
