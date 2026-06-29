---
"hex-app": patch
---

Run the Coach v2 two-lane engine on macOS over the shared observation log and remove the legacy one-shot macOS coach (MC-R4). Objective coaching (fluency + GOP) now runs on-device for free at capture, and the LLM lane auto-batches over the backlog when opted in with a BYOK Gemini key and under budget, appending `CoachObservation` rows and curating Review cards. Settings gains a new English Coach section (opt-in / key / auto-LLM / monthly budget / cloud-upload disclosure) replacing the old pronunciation-coach UI.

Deliberate deviation from the original MC-5: the iOS `Voco/CoachService.swift` was NOT moved into the shared layer (it is the hottest upstream file and sharing it would cause recurring merge conflicts). macOS instead uses a platform-specific `MacCoachService` driver built on the already-shared VocoCore/VocoEngine primitives, mirroring iOS behavior exactly. A future cleanup could extract a shared `CoachRunner` used by both platforms.
