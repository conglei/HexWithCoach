---
"hex-app": minor
---

Coach RC-2 wiring + RC-3 Review feed — coaching is now on screen. Adds a **Review** tab (the new hero): when the Coach is off/keyless it shows an **activation shell** baited with the live captured-backlog count and a "Connect a key" CTA; once a Gemini key is connected it auto-analyzes a bounded slice of the dictation backlog and shows a feed of cards (you-said → more-natural → why → lens, plus positive "win" cards), each with Save / Got it / Not useful / see-in-context actions. A new `CoachService` runs the CE-3 pipeline over the un-analyzed backlog (not per-utterance), persists curated cards (`CoachCardEntity`, CloudKit-synced), updates the LearnerProfile, and tracks a running BYOK cost estimate shown in Settings. `TranscriptEntry` gains a stable `id` and a `coachAnalyzedAt` backlog marker.
