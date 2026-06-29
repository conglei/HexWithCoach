# [CF-3] Progress & accumulation loop

- **Phase:** 3 — Notebook & Coach v2 (Coach surface)
- **Depends on:** CF-1 (summary/focus), CF-2 (typed practice), DM-2 (observation log); extends RC-6 / ProgressDigest
- **Size:** L
- **Design:** this session (accumulation + proof-it-works)

## Problem
Practice isn't recorded or surfaced, and there's no **proof it's working** — so there's no reason
to come back. Professional coaching lives or dies on visible progress: the user must *see* that the
effort moved something. This is also the engagement/retention engine.

## Principles
- **Visible accumulation.** "Today / this week you practiced X" — reps, which lenses/focus areas,
  and the improvement delta. Small, concrete, every session.
- **Proof it's working.** Tie practice back to the focus areas and show the **frequency drop**:
  *"you practiced the /θ/ sound 3× and it fell from 12 to 7 occurrences."* This is the single most
  motivating thing a coaching app can show.
- **Reward, never punish.** Growth-framed and only-up where possible (levels, mastery milestones,
  streak). Nothing the user sees should decrease as a punishment.

## Surface
- **"Today you practiced" strip** (lives in the CF-1 summary): reps, by lens/focus, and the delta vs
  last attempt.
- **Progress view** — per-lens levels over time, focus-area frequency **trends**, mastery
  milestones, streak. Extends the existing `ProgressDigest` / RC-6.
- **Closing the loop** — for a given focus area, plot its occurrences over time and overlay practice
  events → did practicing it reduce its frequency. (This is the CT-1 / CT-2 trend work, folded in
  and made purposeful.)

## Tasks
- [ ] Tag `PracticeAttempt` with `patternKey` + `lens` + `kind` (from the focus area that launched
      the drill — wired in CF-2).
- [ ] Practice-log aggregation (pure, testable): today/week reps, grouped by lens/focus, with deltas.
- [ ] Per-focus **frequency trend** over `CoachObservation` (the practice→drop signal). Build the
      per-pattern / per-word time series the observation log was designed for (CT-1/CT-2).
- [ ] Surface streak (`CoachStreakStore`), mastery milestones (`LearnerProfile`), and per-lens level
      trends.
- [ ] Wire the "Today you practiced" strip into the Coach summary (CF-1).

## Reliability
- Frequency-drop claims must be honest: only show "improved" when the trend is real over enough
  data; avoid declaring victory on noise (same evidence-threshold discipline as CF-1).
- Capture practice/observation snapshots at the time they happen (the `CoachSnapshot` durability
  principle) so the progress curve survives audio/data pruning.

## Acceptance criteria
- [ ] After practicing, the Coach shows what was practiced today + reps + an improvement delta.
- [ ] A focus area shows its occurrence trend with practice events overlaid, demonstrating
      improvement when it genuinely occurred.
- [ ] Streak / per-lens levels / mastery are surfaced; nothing decreases punitively.

## Open questions (for review)
- How aggressively to claim "improved" (evidence threshold for the drop signal).
- Daily vs weekly as the primary accumulation frame (recommend weekly headline + daily reps).
