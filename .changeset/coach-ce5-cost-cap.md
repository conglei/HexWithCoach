---
"hex-app": minor
---

CE-5 monthly cost cap for the iOS Coach: a new pure, unit-tested `CoachBudget` (HexCore) plus per-month spend tracking in `CoachService`. The Coach now estimates BYOK spend per month, enforces an optional cap (Off / $1 / $5 / $10 / $20) before and within each analysis run so it stops the moment the limit is reached, and surfaces "This month" spend, the cap picker, and a "Monthly cap reached" notice in Settings.
