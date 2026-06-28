# [CE-3] Multi-lens extract + critic verify + prioritize + integrate

- **Phase:** 2 — Coach engine (deep)
- **Depends on:** CE-1, CE-2
- **Blocks:** RC-2, RC-6
- **Size:** L
- **Design:** [coach-engine-deep-design.md](../coach-engine-deep-design.md) §3

## Goal
The verified, decomposed analysis that replaces the one-shot prompt (pillar B).

## Tasks
- [ ] **Tier 1 — extract**: per-lens candidate observations across grammar/usage · lexis &
      naturalness · discourse/conciseness · pronunciation · prosody & fluency. Input = transcript +
      audio + word timings + current `LearnerProfile`. Each candidate: span, rule hypothesis,
      native rewrite, severity, `needsAudio`.
- [ ] **Tier 2 — critic**: verify each candidate (real error? rewrite meaning-preserving + genuinely
      more native?); drop low-confidence. (Separate pass vs. self-check — design OQ #2.)
- [ ] **Integrate** survivors into the `LearnerProfile` (CE-2).
- [ ] **Prioritize** the 1–2 highest-leverage focuses (frequency × impact × addressability).
- [ ] Emit per-lens structured results (coach-v2 `PerspectiveFeedback`/`SessionFeedback` shape).

## Acceptance criteria
- [ ] A transcript yields verified, per-lens observations with rules + rewrites (no obvious false
      positives in a manual spot-check).
- [ ] Output updates the profile and names a prioritized focus.
