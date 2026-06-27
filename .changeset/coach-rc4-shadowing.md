---
"hex-app": minor
---

Coach RC-4 shadowing — cards are now practiceable. "Say it better" on an improvement card opens a shadowing flow: hear the natural phrasing (on-device `AVSpeechSynthesizer`), then repeat it; on-device ASR transcribes your repeat and a TDD'd `ShadowingScorer` (word-level, case/punctuation-insensitive) confirms you produced the phrase with a clear success state. Fully offline (TTS + ASR); the optional cloud pronunciation check is a later add. Completing a shadow counts toward the streak (RC-6) — never a forced gate, since reading the rewrite already helps.
