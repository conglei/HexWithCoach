---
"hex-app": minor
---

Coach RC-2 (core): curate the pipeline's verified insights into a small, deduped, positive-leaning set of teachable cards — not one per mistake. Adds `CoachCard` (+ `CoachCardKind`), `CoachCardCurator` (dedupes insights to one card per recurring-pattern key, annotates "came up N×" from the LearnerProfile, leads with a "win" card for newly-mastered habits, orders the rest by severity, and caps per-batch volume), and `CoachCostEstimator` (rough BYOK USD from token counts, tiered by model) — all in HexCore and `swift test`-covered (10 tests, TDD). The iOS service that runs this over the dictation backlog and the Review feed that renders the cards come next (RC-2 wiring + RC-3).
