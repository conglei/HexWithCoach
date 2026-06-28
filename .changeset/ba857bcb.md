---
"hex-app": minor
---

Closed-loop shadowing: when the on-device pronunciation model is present, each shadow attempt is re-scored for per-phoneme goodness-of-pronunciation and the result shows sound-by-sound deltas vs. your previous try (e.g. /θ/ red → green) on top of the existing pass/fail. Without the model, the practice flow is unchanged. (CI-11)
