# [IA-2] Coach activation: baited empty state + first-run nudge

- **Phase:** 3 — Notebook & Coach v2
- **Depends on:** IA-1, RC-3
- **Blocks:** —
- **Size:** S
- **Design:** [review-coach-companion-design.md](../review-coach-companion-design.md) §8 (activation); this session (capture-first decision)

## Goal
Preserve RC-7 / §8's activation payoff under the **capture-first** IA. Since the app now opens into
Home (not the coaching hero), the Coach tab must still convert new users — keep the baited
empty/preview state inside Coach and nudge first-run users toward it.

## Context
IA-1 makes Home (capture) the front door, reversing RC-7's "open into Review." Without a nudge a new
user may never discover coaching — the exact cold-start risk §8 was designed to solve. Coaching is
now opt-in / likely paid, so the entry must *sell* it, not just unlock it.

## Tasks
- [ ] Coach-tab baited empty state (reaffirms the RC-3 activation shell): "You've captured N things
      this week — see how to say them better." Phrase for the opt-in/paid entry, not only BYOK.
- [ ] First-run nudge from Home → Coach (a callout or tab badge) so capture-first users discover coaching.
- [ ] Show the bait only pre-activation; replace/dismiss once coaching is enabled.

## Acceptance criteria
- [ ] A new user who opens into Home is guided to Coach at least once.
- [ ] Coach's pre-activation state explains the payoff using the user's real capture count.
