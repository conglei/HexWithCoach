---
"hex-app": patch
---

Coach: when a sound "came out unclear", tell users what it actually sounded like instead of only flagging it. The "Sounds to work on" row now reads "came out unclear — sounded more like /ɛ/" when the recognizer heard a clear-enough leading production, and the sound detail sheet adds a "What it sounded like" breakdown of your own productions (distinct from the guide's generic "Often swapped for"). Uses the per-phoneme data already captured on-device; no new model or network calls (#86).
