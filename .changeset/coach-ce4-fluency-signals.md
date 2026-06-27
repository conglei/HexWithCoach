---
"hex-app": minor
---

CE-4 objective fluency/prosody signals: words/min (pace), filler rate (um/uh/like/you know/…), and restart/false-start detection, plus pause stats (count, mean pause, long-pause rate) when word timings are available — all computed on-device in HexCore with no LLM and no network. Exposes a structured `metrics[String: Double]` for the prosody/fluency lens and trends (RC-6). The multimodal pronunciation lens (feeding audio+transcript to the model) is handled separately in CE-3.
