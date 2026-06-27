---
"hex-app": patch
---

Coach: run both extraction and the critic on the stronger `flash` model, treat the recorded audio as authoritative and the ASR transcript as a fallible reference, and let the critic hear the audio when verifying pronunciation/prosody candidates. Improves feedback quality and grounding, especially on prosody.
