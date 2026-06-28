# Objective signals author the pronunciation & fluency lenses; the LLM teaches

Now that on-device objective signals exist (GOP from forced alignment; fluency timing stats), the
pronunciation and prosody lenses are **detected deterministically from those signals**, not judged by
the LLM. The LLM owns *detection* only for the meaning lenses (grammar/lexis/discourse) and owns
*teaching* (the rule, native rewrite, practice sentence) for all five. This makes the two
hardest-to-trust lenses free, private, reproducible, and drift-proof, and confines the LLM to where it
is genuinely better (meaning + pedagogy).

## Considered options

- **LLM authors all lenses, objective signals only as grounding** — rejected: keeps pronunciation/
  fluency subjective and drift-prone, the exact weakness we just removed.
- **Absolute GOP thresholds declare patterns** — rejected: GOP is relative (mic, voice, accent), so
  fixed cutoffs would flag a stable accent or a bad recording as errors and bias low-baseline speakers.

## Consequences

- GOP drives a `RecurringPattern` only via **per-speaker-relative ranking + recurrence**: a phoneme
  must score among the learner's *own* worst, repeatedly (≥K instances over ≥N notes). Absolute GOP
  stays a **per-instance visual hint** only.
- The per-speaker baseline is **recomputed as the corpus grows** (learnable in the simple sense); a
  per-phoneme improvement *trend* is deferred to the progress/trends work.
- A **cold-start gate** holds pronunciation patterns off until enough data exists.
- Start simple — relative ranking + recurrence — before anything fancier.
