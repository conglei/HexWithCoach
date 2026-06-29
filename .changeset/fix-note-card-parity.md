---
"hex-app": patch
---

Coach: the Note detail page no longer hides issues that show in the Review tab. Cards whose text span didn't line up with the transcript's word timings were being silently dropped from the note's coaching panel; the panel now shows all of that note's improvement cards (span-matched ones first, in reading order, then the rest) so the note page is always a superset of what Review surfaces for it (#83).
