---
"hex-app": patch
---

Coach: stop falsely flagging correct syllabic pronunciations (e.g. "-ful" → [əl], "little" → [l̩]) as errors. The phoneme analyzer now recognizes when a decoded sound is a syllabic realization of the expected phoneme, credits its GOP instead of marking it red, and no longer reports a bogus "you said /əl/" substitution — which also removes a major source of inflated "schwa came out unclear" counts on long notes (#82).
