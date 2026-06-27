---
"hex-app": minor
---

Coach UX from device testing: (1) the Coach now sends the **audio** alongside the transcript (multimodal lens), so it can hear pronunciation/prosody rather than only reading text; (2) **skip dictations under 10s** — too short to coach on, they roll out of the backlog without spending; (3) History rows show a **processing indicator** (sparkles + issue count when analyzed, an hourglass while pending — only once the Coach has run); (4) a transcript's detail view now **backlinks to the Coach's findings** for that note (the issues detected, or "not reviewed yet" / "no notes"). Also hardens the History list against the duplicate-id case via persistentModelID.
