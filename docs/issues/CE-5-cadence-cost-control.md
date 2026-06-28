# [CE-5] Analysis cadence + cost control

- **Phase:** 2 — Coach engine (deep)
- **Depends on:** CE-1
- **Blocks:** —
- **Size:** M
- **Design:** [coach-engine-deep-design.md](../coach-engine-deep-design.md) §6

## Goal
Make a deep, multi-pass engine affordable over an all-day corpus (BYOK). Replaces macOS's
per-recording auto-analyze, which doesn't scale.

## Tasks
- [ ] **Curated/batched** analysis (not per-utterance): pick a cadence/trigger — daily batch /
      on-open / N-dictations (design OQ #3) — and a sampling/curation strategy so cost is bounded.
- [ ] **Backlog-on-activation**: when a key is first added, analyze the accumulated (curated) backlog.
- [ ] **Model tiering** (from CE-1): cheap extraction, strong critic/synthesis, audio-capable lens.
- [ ] **Surface running cost** (`costUSDEstimate`) so a BYOK user isn't surprised; optional monthly cap.
- [ ] Lean on the free objective signals (CE-4) to carry fluency value without LLM cost.

## Acceptance criteria
- [ ] Analysis never fires once-per-utterance; volume/cost is bounded and visible.
- [ ] First key-connect produces a first batch of results from the backlog.
