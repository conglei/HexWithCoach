# [RC-3] Review tab: feed + activation shell

- **Phase:** 2 — Review/Coach companion
- **Depends on:** RC-2
- **Blocks:** RC-4, RC-5, RC-7
- **Size:** L
- **Design:** [review-coach-companion-design.md](../review-coach-companion-design.md) §5, §8

## Goal
The hero surface: a flickable feed of learnable-moment cards, with a baited activation state.

## Tasks
- [ ] Review feed UI: card list (locked visual language — monochrome + single iOS-blue accent,
      iOS 26 cues) showing context / you-said / more-natural / why / lens.
- [ ] Card actions: Say it better (RC-4), Save (RC-5), Got it / Not useful, play audio, see in context.
- [ ] **Activation shell**: when Coach is off / no key, show the baited empty state with the live
      captured-backlog count + "Connect a key to unlock coaching" CTA → BYOK flow (RC-1).
- [ ] Progress/streak header (full surface in RC-6).
- [ ] Transparent capture note + link to exclusions (RC-8).

## Acceptance criteria
- [ ] Keyless user sees the activation state with a real backlog count.
- [ ] After connecting a key, the feed populates from the analyzed backlog.
