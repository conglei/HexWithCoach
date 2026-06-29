# [MC-R4] macOS Coach v2 on the observation log (re-do MC-5 + carry MC-6)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ◐ MC-5 approach re-applied on main's evolved CoachService; ✅ MC-6 still applies
- **Depends on:** MC-R2, MC-R3
- **Blocks:** MC-R5, MC-R7
- **Size:** L
- **Design:** [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §6

## Goal
Run the Coach v2 two-lane engine on macOS over the shared store, on top of main's *evolved*
`CoachService` (the #81–#89 + DM-2 version) — objective always-on at capture, LLM auto-batched —
appending `CoachObservation` rows and deriving cards/profile as projections.

## Tasks
- [ ] Re-apply the "shared `CoachService` in `VocoEngine`" move on top of main's current CoachService
      (this is the biggest re-apply; main reworked it). Keep iOS green.
- [ ] macOS capture hook: objective lane at save (idempotent via `objectiveAnalyzedAt`); LLM lane
      auto-batched at launch (budget-gated); both append `CoachObservation` before curation.
- [ ] Carry MC-6: remove the legacy one-shot macOS Coach (`VocoMac/Features/Coach/*` legacy +
      `Clients/CoachClient`/Providers) — still present on main's macOS app.
- [ ] macOS `CoachV2SettingsView`: opt-in / BYOK key / autoLLM / budget (reuse `CoachKeychain`).

## Acceptance criteria
- [ ] A macOS capture produces objective observations (keyless) + cards; LLM observations when keyed.
- [ ] iOS coach behavior unchanged; `swift test` green; both apps build.
