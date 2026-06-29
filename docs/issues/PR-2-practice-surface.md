# [PR-2] Practice surface in the Coach tab

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** IA-1, PR-1
- **Blocks:** PR-3
- **Size:** M
- **Design:** this session (Practice mockup); reuse RC-4 (shadowing), RC-5 (phrasebook)

## Goal
Build the Practice surface within the Coach tab: a paste hero at top, coach-generated drills
("Continue"), and the phrasebook promoted out of its hidden bookmark.

## Tasks
- [ ] Section layout: paste hero → "Continue · from your coach" → "Phrasebook".
- [ ] Coach-sourced drills from `CoachCard.practiceText`.
- [ ] Cross-links: Review card "Say it better" → Practice with the target preloaded; note detail
      "practice this line".
- [ ] Streak / progress header.

## Acceptance criteria
- [ ] Practice surface lists coach drills + phrasebook and shows the paste hero.
- [ ] Deep-link from a card preloads its target into Practice.
