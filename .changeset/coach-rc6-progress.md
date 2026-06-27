---
"hex-app": minor
---

Coach RC-6 progress & rewards. The Review tab gains a never-punishing streak header (consecutive days you reviewed/shadowed a card) that expands to a Progress digest: per-lens levels (only-up), "wins" (mastered patterns), and your next focus. Acting on any card counts toward the day's streak. The streak math is a TDD'd, pure HexCore `StreakCalculator` (same-day no-op, consecutive +1, gap resets to 1, best never drops); levels/wins read from the LearnerProfile the engine maintains. No surfaced metric can decrease in a way that reads as a downgrade.
