---
"hex-app": patch
---

Fix two device bugs in the Coach. (1) Every analysis failed with `Gemini request failed: 404` because the model IDs (`gemini-3.1-flash-lite` / `gemini-3.1-flash`) don't exist — corrected to the current `gemini-2.5-flash-lite` (extract) and `gemini-2.5-flash` (critic). (2) After RC-3 added `TranscriptEntry.id`, SwiftData's lightweight migration filled every pre-existing row with the same default UUID, causing "ID occurs multiple times" in History's list and broken card↔transcript links — a one-time launch repair now reassigns duplicate ids.
