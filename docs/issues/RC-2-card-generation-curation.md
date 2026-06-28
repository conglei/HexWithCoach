# [RC-2] Learnable-moment card generation + curation

- **Phase:** 2 — Review/Coach companion
- **Depends on:** CE-3, CE-2, RC-0
- **Blocks:** RC-3
- **Size:** M
- **Design:** [review-coach-companion-design.md](../review-coach-companion-design.md) §5

## Goal
Turn analyzed dictations into a curated set of teachable "cards" — not one per mistake — **and
control analysis cost/volume** (the part that diverges hardest from macOS).

## Reuse
Cards are a **curation/presentation layer over existing `CoachFeedbackEntry`s** (RC-1), not a new
analyzer. "More natural" = `Feedback.nativeRewrite`; "why"/lens from `Issue`/`wins`.

## Tasks
- [ ] **Analysis trigger (NOT macOS's per-recording auto).** macOS auto-analyzes every recording ≥
      `thresholdSec`; all-day cross-app dictation makes that cost/noise-prohibitive. Pick an iOS
      trigger — daily batch / curate-then-analyze a sample / on-demand — and implement it.
- [ ] **Surface running cost** from `costUSDEstimate` so a BYOK user isn't surprised.
- [ ] **Backlog analysis on activation**: when a key is first added, analyze the accumulated
      (curated) backlog for the instant first-payoff.
- [ ] Derive cards from feedback: snippet + `nativeRewrite` + one-line why + lens + source/time.
- [ ] **Mix wins with improvements** (positive-leaning); emit "win" cards for natural phrasings.
- [ ] **Curate + limit volume**: highest-value moments only; dedupe recurring issues into one
      pattern card ("dropped articles 4× — here's the pattern"). Per-day cap tunable.

## Acceptance criteria
- [ ] Analysis does not fire once-per-utterance; volume/cost is bounded and the estimate is visible.
- [ ] From a day of dictations, a small, deduped, positive-leaning set of cards is produced, each
      linking back to its `Transcript`/`CoachFeedbackEntry`.
