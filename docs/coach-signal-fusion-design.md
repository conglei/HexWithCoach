# Coach — Signal Fusion & Frictionless Journey (Coaching Integration)

Status: **decisions locked** via design grilling (2026-06-28). Glossary in [CONTEXT.md](../CONTEXT.md);
decision records in [docs/adr/0001–0004](adr). Extends [coach-engine-deep-design.md](coach-engine-deep-design.md)
(the four pillars) and the shipped baseline (#57 pronunciation pipeline, #58 coach-card context/practice).

## 0. Where we are (grounded in code)

Deep-design pillars A (Learner Profile), B (extract→critic), and the *text* side of D are live. Pillar
C deferred phoneme-level scoring "until the rest proves out" — and that depth pass now **exists** (#57):
`CTCForcedAligner` + `PronunciationAnalyzer` produce per-phoneme **GOP** at ~20 ms. But it isn't wired
into coaching, and two objective signals go to waste:

1. **Word timings** are captured but never passed to the pipeline → `FluencySignals` pause/rate stats
   are always zero.
2. **Pronunciation GOP** is siloed in the standalone "Check pronunciation" sheet → the coach's
   pronunciation lens is still the LLM guessing from audio.

## 1. Principle

> **Measure what we can; ask the LLM what we can't; fuse into one profile, one feed, one practice loop —
> and the measured part is a complete coach on its own.**

| Lens | Detected by | Why |
|---|---|---|
| Pronunciation (segmental) | **Objective** — GOP | Measurable; LLM-from-audio is unreliable |
| Prosody — *timing* (pace/pauses/fillers) | **Objective** — word timings | Deterministic, free |
| Prosody — *intonation/stress* | **LLM** (audio) | Only the LLM can hear it; no objective signal yet |
| Grammar / lexis / discourse | **LLM** (text) | Meaning-level; not measurable |

**Keyless-first (ADR-0002):** the objective lane is a *complete, free, on-device coach* for
pronunciation + fluency. A BYOK key is an **upsell** that adds the meaning lenses, intonation, and
richer LLM-authored teaching — never a gate.

## 2. Detection rules (ADR-0001)

- **GOP → pattern** only via **per-speaker-relative ranking + recurrence + cold-start gate**. Absolute
  GOP is a per-instance visual hint only. The per-speaker baseline is recomputed as the corpus grows
  (learnable); per-phoneme improvement *trends* come later.
- **Fluency → pattern**: fillers / long-pauses / restarts via light **absolute thresholds + recurrence**.
  **Pace is informational** in V1 (relative flagging later). All fluency numbers are always fed to the
  LLM as grounding.
- The **prosody lens is split**: timing measured, intonation judged.

## 3. The keyless coach (ADR-0002, ADR-0003)

Without a key, a learner still gets the full notice→practice→reinforce loop for pronunciation + fluency:

- **Detection**: objective (above).
- **Teaching (deterministic)**: a bundled **phoneme guide** (~40 EN phonemes: description,
  how-to-articulate, common L1 substitutions, practice sentence + minimal pair) + a small **fluency-tips
  table**. Authored once offline (LLM-assisted, human-reviewed), shipped as versionable data. Cards =
  guide content + the learner's own flagged examples.
- **Practice**: shadow (TTS → record → ASR), now closed with **GOP re-scoring** on the attempt.
- **L1**: asked once at onboarding (optional), used as a keyless prioritization prior via a bundled
  L1→interference table. Never inferred (ADR-0003).

With a key, the LLM **enriches** the objective cards (personalized prose, L1-aware) and adds the
meaning + intonation lenses.

## 4. The two-lane pipeline (ADR-0004)

```
note transcribed
   │
   ├── OBJECTIVE LANE  (free, local, AUTOMATIC on capture, persisted with the note)
   │     GOP + fluency signals → relative+recurrence patterns → deterministic teaching → cards
   │     no critic (the measurement is authoritative)
   │
   └── LLM LANE  (BYOK, AUTOMATIC but batched + budget-capped + toggle)
         extract (grammar/lexis/discourse from text · intonation/stress from audio)
           → critic verify → patterns → teach/enrich
   │
   └── both merge into the Learner Profile + the Review feed
```

- Objective results are **persisted per note** (like word timings) and shown **inline** — no manual
  "Check pronunciation" button, no per-utterance trigger.
- LLM extract **drops** segmental pronunciation + timing-fluency (objective owns them) and is given the
  objective findings as grounding; the critic only verifies LLM candidates.

## 5. Surfaces & journey

- **Layered note view** — the synced transcript *is* the coaching surface: GOP-tinted words, pause /
  filler markers, and (keyed) grammar/word-choice spans, all on one timeline. Tap a word → phoneme
  detail; tap a span → card.
- **Review feed** — the prioritized **cross-note curriculum** (the 1–2 focuses + recurring patterns +
  wins). The note view is inspection; the feed is the path.
- **Progress** — per-lens trends now backed by objective data (GOP trend, filler trend, mastered phonemes).

## 6. Model delivery — download-on-demand

- **Host** the model (FP16 static ~603 MB to start; shrink to palettized ~230 MB / wav2vec2-base
  ~190 MB later). Reuse the releases S3 or HF.
- **Download** on first pronunciation use → `Library/Application Support/Pronunciation/` (the sideload
  path), load at runtime as today.
- **Streaming, resumable `URLSession` download task to disk** — *not* FluidAudio's in-memory `data(for:)`
  (which OOM-kills on the big file). Checksum, cancel/resume, visible size + progress.
- **Keyless-no-model state**: fluency coaching works immediately; an "enable pronunciation (~Xmb)"
  prompt offers the download; GOP backfills recent notes once present.

## 7. Task queue (CI series — ordered, dependency-aware)

| ID | Task | Depends | Gated on model | Size |
|----|------|---------|---|---|
| **CI-1** | Pass `wordTimings` into the pipeline → real fluency signals in prompt + profile | — | no | S |
| CI-2 | Objective **fluency patterns** (fillers/pauses/restarts: absolute + recurrence + cold-start) → profile, keyless | CI-1 | no | M |
| CI-3 | **Pronunciation signals** in analysis: run GOP, `PronunciationSignals`, per-speaker-relative + recurrence patterns; persist per-note result | — | dev via sideload | L |
| CI-4 | **Keyless teaching assets**: bundled phoneme guide + fluency-tips + L1→interference tables; deterministic objective-card generation | CI-2, CI-3 | no | M |
| CI-5 | **Keyless-first reframe**: ungate Review on key; activation shell = free coaching + key upsell | CI-2/CI-4 | no | M |
| CI-6 | **LLM lane scoping**: extract = meaning (text) + intonation (audio); drop pronunciation/timing; feed objective findings to teaching; critic verifies LLM only | CI-2, CI-3 | no | M |
| CI-7 | **Two-lane automation**: objective auto-on-capture (debounced, persisted); LLM auto-batched + budget-capped + toggle; remove manual buttons | CI-3, CI-6 | partial | M |
| CI-8 | **Download-on-demand** model delivery (streaming/resumable downloader, checksum, enable prompt) | CI-3 | — | M |
| CI-9 | **Inline layered note view** (GOP coloring + pause/filler markers + spans on the synced transcript) | CI-3 | partial | L |
| CI-10 | **L1 onboarding** (ask once, optional) + wire interference prioritization | CI-4 | no | S |
| CI-11 | **Closed-loop shadowing**: re-score GOP on the attempt; per-phoneme deltas | CI-3 | yes | M |
| CI-12 | **Progress/trends across lenses** (GOP/filler/pace trends, mastered phonemes) — extends RC-6 | CI-2/CI-3 | partial | M |

**First PR = CI-1** (no gating, pure plumbing). Then CI-3 (pronunciation, dev via sideload) and CI-8
(delivery) in parallel; CI-4/CI-5 turn it into the keyless product; CI-7/CI-9/CI-11/CI-12 are the
frictionless + retention payoff.

## 8. Resolved decisions & remaining open items

Locked (see ADRs): authority/calibration (0001), keyless-first (0002), ask-L1 (0003), two-lane
automation (0004), keep-LLM-audio-for-intonation, prosody split, pace-informational.

Still genuinely open (tuning, not architecture):
1. **Threshold values** — the recurrence K / cold-start N for GOP and fluency patterns; the
   per-speaker-relative cutoff. Tune on real corpora.
2. **Model size for shipping** (CI-8) — FP16 603 MB first, or invest in palettization/base before
   exposing the download.
3. **Intonation** — re-add as an LLM audio lens vs. a future pitch-based objective signal.
