# Analysis runs automatically in two lanes: free objective always-on, paid LLM auto-batched

Coaching analysis is **automatic**, split by cost:

- **Objective lane (free, local): always-on at capture.** When a note is transcribed, GOP + fluency
  signals run in the background and are **persisted with the note**. The note's pronunciation/fluency
  is shown **inline** on the synced transcript — no manual "Check pronunciation" / "analyze" button.
- **LLM lane (paid, BYOK): automatic but batched and budget-capped.** The meaning-lens + intonation
  pass runs in the background over a backlog (not per-utterance), hard-bounded by the existing monthly
  budget, with a manual "Review now" override and an on/off setting.

## Consequences

- Removes "Review now" as the *primary* path and the per-note "Check pronunciation" button; coaching
  "just appears."
- **Automatic = automatic spend** for the LLM lane — hence the budget cap + toggle are load-bearing,
  not optional. The objective lane is free, so it's unconditionally on.
- Per-note pronunciation/fluency results are **persisted** (like word timings) so opening a note is
  instant and battery is spent once, lazily after save.
- Pairs with ADR-0002: the always-on free lane *is* the keyless coach; the LLM lane is the upsell.
