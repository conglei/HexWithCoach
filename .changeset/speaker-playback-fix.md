---
"hex-app": patch
---

iOS: fix note and shadowing audio playing through the quiet earpiece instead of the main speaker. Recording leaves the audio session routed to the receiver; playback now resets it to `.playback` so it comes out the speaker at full volume.
