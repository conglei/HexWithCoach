---
"hex-app": minor
---

Coach foundation (CE-2): the Learner Profile — the persistent, evolving per-user model that turns one-shot tips into real coaching (pillar A, "the moat"). Adds `LearnerProfile`, `RecurringPattern`, `Lens`, `PatternStatus`, `LexicalProfile`, and a `LearnerProfileStore` (JSON persistence) to HexCore, plus the deterministic update logic that merges verified observations from the pipeline: repeated occurrences raise a pattern's frequency and recency, statuses transition active → improving → mastered purely from how long a pattern has gone without recurring (auditable, never drifts run-to-run), and per-lens levels are growth-framed (only ever increase). No LLM involved in the profile math — fully unit-tested.
