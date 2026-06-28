# Hex Coach

The coaching domain: turning a learner's all-day captured speech into personalized, multi-lens
feedback and practice. (Hex's macOS dictation/transcription domain is separate and not modeled here.)

## Language

**Lens**:
One of the five dimensions the coach evaluates speech along: grammar, lexis (word choice), discourse
(clarity/conciseness), pronunciation, prosody (pace/pauses/fillers).
_Avoid_: perspective, category, dimension

**Objective signal**:
A coaching measurement computed deterministically on-device from ASR output, with no LLM — i.e. GOP
and fluency timing stats. It is the *authoritative source of detection* for the pronunciation and
prosody lenses.
_Avoid_: metric (reserve "metric" for the rounded trend values stored over time)

**GOP** (Goodness of Pronunciation):
A per-phoneme score (≤ 0; closer to 0 = better) from forced alignment, expressing how confidently the
audio matches the expected phoneme. The objective signal behind the pronunciation lens.

**Learner Profile**:
The persistent, per-user, evolving model the coach conditions on and updates every analysis: level per
lens, recurring patterns, inferred L1, goals. The product's moat.
_Avoid_: user model, learner state

**Phoneme guide**:
The bundled, static reference (~40 English phonemes: description, how-to-articulate, common L1
substitutions, a practice sentence + minimal pair) that powers keyless pronunciation teaching and
practice. Authored once, versionable; the LLM enriches it per-learner when a key is present.

**Recurring Pattern**:
A tracked, repeating issue (or, once gone, a mastered "win") within one lens, carrying frequency,
recency, status, and the learner's own real examples. Patterns are the curriculum.
_Avoid_: issue, mistake, insight (an "insight" is a single observation; a pattern accumulates many)

**Detection vs Teaching** (authorship split):
*Detection* = deciding a pattern exists. *Teaching* = authoring the human-facing card (the rule, the
native rewrite, the practice sentence). Detection ownership by lens:
- **Objective layer**: pronunciation (GOP) + the *timing* part of prosody (pace, pauses, fillers).
- **LLM (multimodal)**: grammar, lexis, discourse (from text) + the *intonation/stress* part of
  prosody (from audio — the one thing only the LLM can hear).
Teaching has a **deterministic keyless baseline** for the objective lenses (templated per-phoneme
guidance + practice sentence), which the LLM *enriches* when a key is present; teaching for the meaning
+ intonation lenses requires the LLM. So the **prosody lens is split** (timing measured, intonation
judged), and the app is a full coach with **no key** — the key is an upsell, not a gate (ADR-0002).
