# [CE-2] Learner Profile: model, store, update logic

- **Phase:** 2 — Coach engine (deep)
- **Depends on:** CE-1
- **Blocks:** CE-3, RC-2, RC-6
- **Size:** L
- **Design:** [coach-engine-deep-design.md](../coach-engine-deep-design.md) §2

## Goal
The persistent, evolving per-user model that turns tips into coaching — **the moat** (pillar A).

## Tasks
- [ ] `LearnerProfile` (Codable, in HexCore): `inferredL1`, `interferencePatterns`, `levels[Lens]`,
      `patterns[RecurringPattern]`, `lexicalProfile`, `registerTendencies`, `goals`, `updatedAt`.
- [ ] `RecurringPattern`: lens, summary, rule, frequency, recency, `status (.active/.improving/
      .mastered)`, `examples[ExampleRef → transcriptID + span]`.
- [ ] Persistence (file-JSON in HexCore; syncable later via P4-2 path).
- [ ] **Update logic**: merge verified observations from the pipeline (CE-3) → increment frequency,
      update recency/status, recompute levels/trends. Keep it **stable/auditable** (don't let the
      profile drift run-to-run).
- [ ] L1: infer vs. ask once (see design OQ #5) — pick and implement.

## Acceptance criteria
- [ ] Repeated occurrences of the same issue raise a pattern's `frequency` and update `recency`.
- [ ] A pattern can transition to `.mastered`; levels move only in growth-framed ways.
