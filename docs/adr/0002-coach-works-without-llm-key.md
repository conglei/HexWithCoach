# The coach works without an LLM key; the key is an enhancement, not a gate

The objective layer (pronunciation GOP + fluency timing) already delivers real, personalized coaching
for the pronunciation and prosody lenses — free, local, private. So the app must be a **complete coach
with no BYOK key**: detection (objective) + deterministic templated teaching + practice (TTS / ASR /
GOP re-scoring), all on-device. A BYOK key is an **upsell** that unlocks the meaning lenses
(grammar/lexis/discourse), the intonation lens, and richer LLM-authored teaching prose — it does not
gate the app.

## Consequences

- **Review can no longer gate on key presence.** The activation shell stops being "connect a key or
  nothing happens"; it becomes "here's your pronunciation/fluency coaching — add a key for
  grammar/word-choice/clarity too."
- **The objective lenses need a deterministic teaching layer** — templated per-phoneme guidance and a
  practice sentence — so pronunciation/fluency cards generate end-to-end with zero LLM. The LLM, when a
  key is present, *enriches* that teaching rather than being required for it. (Refines ADR-0001's "LLM
  owns teaching": for the objective lenses, teaching has a keyless deterministic baseline.)
- **Strengthens the privacy story**: a genuinely free, fully on-device coaching tier; the cloud is opt-in.
- The keyless tier still needs the pronunciation model on-device (download-on-demand), but no API key.
