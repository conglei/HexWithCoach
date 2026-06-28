# [RC-8] Privacy & capture controls

- **Phase:** 2 — Review/Coach companion
- **Depends on:** RC-0
- **Blocks:** —
- **Size:** M
- **Design:** [review-coach-companion-design.md](../review-coach-companion-design.md) §9

## Goal
Make "capture everything you speak across apps" defensible: easy, granular exclusion.

## Tasks
- [ ] **Per-app exclude list** — never capture/analyze dictation into chosen apps (banking,
      1Password, specific chats).
- [ ] **Incognito dictation** toggle — a quick "don't save this one" mode in the keyboard.
- [ ] **Auto-skip secure fields** (password/secure text entry) — never capture.
- [ ] **Transparency**: onboarding clearly states capture is happening (text + audio, local) with
      exclusions one tap away; reaffirm at the Coach (cloud) opt-in with provider disclosure.
- [ ] Capture stays **local by default**; analysis stays **opt-in + BYOK**.

## Acceptance criteria
- [ ] Dictation into an excluded app / incognito / a secure field produces no stored `Transcript`.
- [ ] Onboarding discloses capture; Coach opt-in discloses cloud upload + provider.
