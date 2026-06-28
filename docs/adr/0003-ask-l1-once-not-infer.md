# Ask the learner's L1 once; don't infer it

The learner's first language is asked **once at onboarding** (optional, skippable) rather than inferred
from speech. L1 is a high-yield personalization prior — it prioritizes which pronunciation patterns to
surface (via a bundled L1→typical-interference table that pairs with the phoneme guide) — and asking is
free, reliable, and works **keyless**. Inference would require an LLM call (unavailable in the keyless
tier per ADR-0002) and is unreliable from a few utterances.

## Consequences

- L1 is a **booster, not a gate**: with no L1, detection still works (per-speaker-relative ranking);
  with L1, keyless pronunciation coaching is prioritized by known interference patterns.
- A small bundled **L1 → interference** table is needed (sibling of the phoneme guide).
- With a key, the LLM may refine/confirm interference patterns, but L1 itself never depends on it.
