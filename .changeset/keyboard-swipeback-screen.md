---
"hex-app": patch
---

Fix the keyboard-bounce flow: starting a Flow Session (e.g. tapping the keyboard mic with no live session → `hexkb://startSession`) now shows a dedicated full-screen "Dictation is on — swipe back to your app" screen instead of dumping you on whatever tab was last open (often Settings). The screen confirms the session is live, shows how long it stays on, and offers "Got it" / "Turn off dictation". Ending the session dismisses it.
