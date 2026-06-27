---
"hex-app": patch
---

Coach: run both extraction and the critic on the stronger `flash` model, treat the recorded audio as authoritative and the ASR transcript as a fallible reference, and let the critic hear the audio when verifying pronunciation/prosody candidates. Pronunciation and prosody feedback is now specific and grounded in the audio — naming the exact sound/syllable, a readable phonetic target, and a concrete articulation or stress fix — and renders as a "Say it like" cue. Improves feedback quality and grounding.
