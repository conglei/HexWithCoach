# [MC-R6] macOS Practice surface (PR-2 on the Mac)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ➕ new (no MC equivalent; from Phase-3 PR-2)
- **Depends on:** MC-R2 (PracticeItem shared), MC-R5
- **Blocks:** —
- **Size:** M
- **Design:** PR-1 (PracticeItem), PR-2 (Practice surface); [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §5

## Goal
Build the Practice surface inside the macOS Coach hub over the shared `PracticeItem` model: paste hero
→ coach-generated drills ("Continue") → phrasebook.

## Tasks
- [ ] Section layout: paste hero → "Continue · from your coach" (from `CoachCard.practiceText`) → Phrasebook.
- [ ] Deep-link: Review card "Say it better" → Practice with target preloaded.
- [ ] PracticeItems persist (synced) and never appear in History.
- [ ] Streak / progress header (shared with MC-R7).

## Acceptance criteria
- [ ] Practice lists coach drills + phrasebook + paste hero; deep-link preloads a target.
- [ ] `xcodebuild build -scheme VocoMac` succeeds.
