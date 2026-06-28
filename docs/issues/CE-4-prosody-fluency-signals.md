# [CE-4] Objective prosody/fluency signals + multimodal pronunciation lens

- **Phase:** 2 — Coach engine (deep)
- **Depends on:** CE-1
- **Blocks:** —
- **Size:** M
- **Design:** [coach-engine-deep-design.md](../coach-engine-deep-design.md) §4

## Goal
Actually *hear* the speaker — real signals, not LLM vibes (pillar C), per the locked tiered approach.

## Tasks
- [ ] **Objective signals, local + free** from the ASR transcript + **word timings**: words/min
      (pace), pause distribution, **filler rate** (um/uh/like), restarts/false-starts. Feed the
      fluency/prosody lens + metrics/trends.
- [ ] **Multimodal pronunciation lens**: feed **transcript + audio** to an audio-capable model
      (stop withholding the transcript).
- [ ] Expose metrics as structured `metrics[String: Double]` on the lens output (for trends/RC-6).

## Deferred (not V1)
- [ ] Phoneme-level scoring (which sounds you miss) via forced alignment / Apple Speech analytics /
      dedicated model — a later depth pass.

## Acceptance criteria
- [ ] A dictation produces real fillers/min + pace numbers computed locally (no LLM needed).
- [ ] The pronunciation lens receives the transcript alongside the audio.
