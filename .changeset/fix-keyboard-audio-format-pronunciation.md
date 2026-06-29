---
"hex-app": patch
---

Fix pronunciation analysis silently failing on keyboard-dictated notes: the Flow Session keyboard records audio in the device-native format (e.g. 48 kHz stereo), so the GOP loader now resamples/down-mixes any source to 16 kHz mono instead of rejecting it.
