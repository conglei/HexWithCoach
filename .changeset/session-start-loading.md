---
"hex-app": patch
---

Smooth out the keyboard-bounce cold start. The first dictation after a cold launch spends ~18s compiling the on-device speech model, and the bounce used to show nothing until it finished. Now the swipe-back screen appears immediately in a "Preparing dictation…" state (with model-load progress and a Cancel), then flips to "Dictation is on" the moment the session is live.
