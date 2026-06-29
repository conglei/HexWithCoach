# iOS Keyboard-First — Issue Backlog

Local issue tracker derived from
[ios-keyboard-v1-implementation.md](../ios-keyboard-v1-implementation.md) and
[ios-keyboard-v1-plan.md](../ios-keyboard-v1-plan.md).

> **UI design is LOCKED** — see [ios-ui-design-v1.md](../ios-ui-design-v1.md) (monochrome +
> single iOS-blue accent, iOS 26 cues, floating tab bar). It governs **P1-3** (host UI),
> **P2-2** (keyboard UI), and **X-1** (onboarding).

> These are local markdown issues (not GitHub issues). Status legend:
> `TODO` · `IN-PROGRESS` · `BLOCKED` · `DONE`.

## Suggested order

Do **SPIKE-1** early (de-risks the whole architecture). Then Phase 0 → 1 (low-risk,
independently shippable). Phases 2 + 3 are tightly coupled. Phase 4 last.

| ID | Title | Phase | Depends on | Size | Status |
|----|-------|-------|-----------|------|--------|
| [SPIKE-1](SPIKE-1-background-audio-survival.md) | Background-audio session survival probe | risk spike | — | S | PASSED ✅ (on device) |
| [P0-1](P0-1-package-multiplatform.md) | Make HexCore `Package.swift` multiplatform | 0 | — | S | DONE |
| [P0-2](P0-2-decouple-settings-input-types.md) | Decouple settings/input models from Sauce + Cocoa | 0 | P0-1 | M | DONE |
| [P0-3](P0-3-ios-permission-sleep-clients.md) | iOS `PermissionClient` + `SleepManagementClient` | 0 | P0-1 | M | DONE |
| [P0-4](P0-4-move-engine-into-hexcore.md) | Move transcription engine into HexCore | 0 | P0-1 | L | TODO |
| [P1-1](P1-1-ios-app-target.md) | Create `HexiOS` app target | 1 | P0-2, P0-3, P0-4 | S | DONE (target `HexIOS`) |
| [P1-2](P1-2-ios-recording-client.md) | iOS `RecordingClient` (AVAudioSession) | 1 | P1-1 | M | PROTOTYPE (AudioRecorder in HexIOS; migrate to HexCore later) |
| [P1-3](P1-3-ios-host-ui.md) | iOS host UI + reuse TCA features | 1 | P1-2 | L | PROTOTYPE (SwiftUI+@Observable; WhisperKit-direct, no TCA yet) |
| [P2-1](P2-1-keyboard-target-app-group.md) | `HexKeyboard` extension + App Group | 2 | P1-1 | M | DONE (target `HexIOSKeyboard`) |
| [P2-2](P2-2-keyboard-ui.md) | Mic-centric keyboard UI + insertion | 2 | P2-1 | M | DONE |
| [P2-3](P2-3-ipc-layer.md) | IPC layer (App Group + Darwin notifications) | 2 | P2-1 | M | DONE |
| [P2-4](P2-4-bounce-and-swipe-back.md) | Keyboard→app bounce + swipe-back screen | 2 | P2-3 | M | DONE (bounce-per-dictation; continuous session = P3-1) |
| [P2-5](P2-5-keyboard-editing-controls.md) | Keyboard in-place editing controls (control surface) | 2 | P2-2 | M | TODO |
| [P3-1](P3-1-session-controller.md) | Continuous session controller + timeout | 3 | SPIKE-1, P2-4 | DONE ✅ (works on device) |
| [P3-2](P3-2-app-intent-shortcuts.md) | App Intent (Shortcuts / Action Button) | 3 | P3-1 | S | DONE (device-test pending) |
| [P3-3](P3-3-live-activity-session.md) | Flow-Session Live Activity (Dynamic Island) | 3 | P3-1 | M | TODO (V1) |
| [P4-1](P4-1-settings-vocab-sync.md) | iCloud sync: settings + vocab | 4 | P1-3 | M | TODO |
| [P4-2](P4-2-history-sync-cloudkit.md) | iCloud sync: history (CloudKit) | 4 | P1-3 | L | TODO |
| [P4-3](P4-3-audio-sync-optin.md) | iCloud sync: opt-in audio assets | 4 | P4-2 | M | TODO |
| [X-1](X-1-onboarding-flow.md) | Onboarding flow | cross-cutting | P2-2 | M | TODO |
| [X-2](X-2-project-structure-ci.md) | Project structure + multiplatform CI | cross-cutting | P0-1 | S | TODO |

## Milestones

- **M0 — Engine portable:** P0-1..P0-4 (HexCore builds for iOS + macOS).
- **M1 — Standalone iOS app:** P1-1..P1-3 (record → transcribe → history on device).
- **M2 — Dictation works:** P2-1..P2-4 (speak into any app).
- **M3 — Wispr-style UX:** P3-1, P3-2, X-1 (sessions + Shortcuts + onboarding).
- **M4 — Cross-device:** P4-1..P4-3 (Mac ↔ iOS sync).

## Phase 2 — Review/Coach companion (the differentiator)

The English-improvement layer that mines real daily speech. Design:
[review-coach-companion-design.md](../review-coach-companion-design.md). Phase 1 substrate is built
on `main`; this turns the accumulated corpus into coaching. **RC-7 is a delta to the locked iOS IA**
— coordinate before editing [ios-ui-design-v1.md](../ios-ui-design-v1.md).

| ID | Title | Depends on | Size | Status |
|----|-------|-----------|------|--------|
### Deep Coach Engine (CE series — the core IP)

The existing macOS engine is a stateless one-shot tip generator and is **too superficial** to be the
product's engine. It is **replaced** by a corpus-stateful pipeline. Design:
[coach-engine-deep-design.md](../coach-engine-deep-design.md). This is the **critical path** — the
surfaces are thin without it.

| ID | Title | Depends on | Size | Status |
|----|-------|-----------|------|--------|
| [CE-1](CE-1-engine-foundation.md) | Engine foundation + provider transport in HexCore + iOS BYOK | — | L | TODO |
| [CE-2](CE-2-learner-profile.md) | Learner Profile: model, store, update logic (the moat) | CE-1 | L | TODO |
| [CE-3](CE-3-multilens-verify-pipeline.md) | Multi-lens extract + critic verify + prioritize + integrate | CE-1, CE-2 | L | TODO |
| [CE-4](CE-4-prosody-fluency-signals.md) | Objective prosody/fluency signals + multimodal pronunciation | CE-1 | M | TODO |
| [CE-5](CE-5-cadence-cost-control.md) | Analysis cadence + cost control (curated/batched, model tiering) | CE-1 | M | TODO |

### Review/Coach surfaces (RC series — consume the engine)

| ID | Title | Depends on | Size | Status |
|----|-------|-----------|------|--------|
| [RC-0](RC-0-substrate-prereqs.md) | Substrate prereqs: audio retention + dictations persisted as `Transcript` | — | S | TODO |
| ~~[RC-1](RC-1-coach-engine-to-hexcore.md)~~ | ~~Port Coach engine~~ → **SUPERSEDED by CE-1..CE-5** | — | — | SUPERSEDED |
| [RC-2](RC-2-card-generation-curation.md) | Learnable-moment card generation + curation | CE-3, CE-2, RC-0 | M | TODO |
| [RC-3](RC-3-review-tab-feed.md) | Review tab: feed + activation shell | RC-2 | L | TODO |
| [RC-4](RC-4-shadowing-practice.md) | Shadowing practice (rephrase → TTS → repeat) | RC-3 | M | TODO |
| [RC-5](RC-5-phrasebook.md) | Save / phrasebook | RC-3 | S | TODO |
| [RC-6](RC-6-progress-rewards.md) | Progress & rewards (streak, deltas, wins, level, digest) | CE-2, CE-3 | L | TODO |
| ~~[RC-7](RC-7-ia-reshuffle.md)~~ | ~~IA reshuffle: Review home, History → search~~ → **SUPERSEDED by [IA-1](IA-1-tab-restructure-coach.md)** | — | — | SUPERSEDED |
| [RC-8](RC-8-privacy-capture-controls.md) | Privacy & capture controls (per-app exclude, incognito) | RC-0 | M | TODO |

- **M-Engine — Deep coach works:** RC-0, CE-1, CE-2, CE-3 (+CE-4/CE-5) — verified, personalized analysis.
- **M-Review — Activation:** RC-2, RC-3 (curated cards → feed → BYOK activation).
- **M-Coach — Loop closed:** RC-4, RC-5, RC-6 (shadow, save, progress/reward).
- **M-Companion — Front door:** ~~RC-7~~ → IA-1 (Phase 3), RC-8 (capture controls).

## Phase 3 — Notebook & Coach v2

A dedicated **Practice** experience (incl. paste-your-own), a scalable **History**
(Notes/Dictation, pagination, delete), the **Coach** tab merge (Review + Practice), and the
**data-model foundation** (lean row + analysis sidecar + observation log) that makes cross-note
coaching durable. Data-model design:
[transcript-analysis-split-plan.md](../transcript-analysis-split-plan.md). **IA-1 supersedes the
RC-7 plan** — Home keeps capture, History stays primary, Review+Practice merge.

### Foundation (data model) — do first
| ID | Title | Depends on | Size | Status |
|----|-------|-----------|------|--------|
| [DM-1](DM-1-transcript-analysis-split.md) | Split TranscriptEntry + analysis sidecar | — | M | TODO |
| [DM-2](DM-2-coach-observation-log.md) | CoachObservation log + curation/profile as projections | DM-1 | L | TODO |

### History scaling
| ID | Title | Depends on | Size | Status |
|----|-------|-----------|------|--------|
| [HS-1](HS-1-history-notes-dictation-segment.md) | History: Notes/Dictation segment | — | S | TODO |
| [HS-2](HS-2-history-windowed-fetch.md) | History: windowed fetch + date-scope chips | DM-1, HS-1 | M | TODO |
| [HS-3](HS-3-history-delete-cascade.md) | History: delete + cascade | DM-1, DM-2 | M | TODO |

### Navigation
| ID | Title | Depends on | Size | Status |
|----|-------|-----------|------|--------|
| [IA-1](IA-1-tab-restructure-coach.md) | Tab restructure: merge Review+Practice → Coach (supersedes RC-7) | — | M | TODO |
| [IA-2](IA-2-coach-activation.md) | Coach activation: baited empty state + first-run nudge | IA-1, RC-3 | S | TODO |

### Practice
| ID | Title | Depends on | Size | Status |
|----|-------|-----------|------|--------|
| [PR-1](PR-1-practice-item-model.md) | PracticeItem model + store | — | S | TODO |
| [PR-2](PR-2-practice-surface.md) | Practice surface in the Coach tab | IA-1, PR-1 | M | TODO |
| [PR-3](PR-3-paste-ingest.md) | Paste-to-practice ingest → segment → shadowing | PR-1, PR-2 | M | TODO |

### Future / not yet scoped
- **PR-4** — Practice Share Extension ("Share → Voco: Practice") — depends PR-3.
- **HS-4** — Dictation auto-expiry (prune dictations older than N days; keep notes) — depends DM-1.
- **CT-1** — Per-word pronunciation trends UI (query `CoachObservation`) — depends DM-2.
- **CT-2** — Pattern frequency/regression + evidence-trail UI — depends DM-2.

**Suggested order:** DM-1 → DM-2 (foundation), alongside HS-1; then HS-2, HS-3, IA-1; then
PR-1 → PR-2 → PR-3; CT-* after DM-2.
## macOS Companion (MC series — bring Coach v2 + synced Notebook to the Mac)

Make macOS a first-class peer: shared synced data model, Coach v2 engine, a real companion window
(Review / Notebook / History / Progress / Shadowing), and Mac↔iOS sync of notes + coach results +
profile + (opt-in) audio. The Coach engine is already shared in `VocoCore`/`VocoEngine`; the gap is
the app-integration layer. Design: [macos-companion-v1-design.md](../macos-companion-v1-design.md).

| ID | Title | Phase | Depends on | Size | Status |
|----|-------|-------|-----------|------|--------|
| [MC-1](MC-1-shared-swiftdata-models.md) | Shared SwiftData models in VocoEngine (linchpin) | 1 | — | L | DONE |
| [MC-2](MC-2-shared-cloudkit-container.md) | Shared CloudKit container + cross-device merge spike | 1 | MC-1 | M | IN-PROGRESS (code; device verify pending) |
| [MC-3](MC-3-macos-swiftdata-store-migration.md) | macOS adopts shared SwiftData store + JSON migration | 1 | MC-1 | L | DONE |
| [MC-4](MC-4-profile-sync.md) | Sync LearnerProfile + growth history | 1 | MC-1 | M | DONE |
| [MC-5](MC-5-macos-coach-v2-engine.md) | Wire Coach v2 two-lane engine on macOS | 2 | MC-3, MC-4 | DONE |
| [MC-6](MC-6-remove-old-macos-coach.md) | Remove legacy macOS one-shot Coach | 2 | MC-5 | M | DONE |
| [MC-7](MC-7-companion-window-shell.md) | macOS companion window shell | 3 | MC-3 | M | DONE |
| ~~[MC-8](MC-8-macos-review-feed.md)~~ | macOS Review feed → **SUPERSEDED by [MC-R5](MC-R5-macos-coach-hub.md)** | 3 | — | — | SUPERSEDED |
| ~~[MC-9](MC-9-macos-notebook.md)~~ | macOS Notebook → **folded into capture + [MC-R6](MC-R6-macos-practice-surface.md)** | 3 | — | — | SUPERSEDED |
| ~~[MC-10](MC-10-macos-progress.md)~~ | macOS Progress → **SUPERSEDED by [MC-R7](MC-R7-macos-progress.md)** | 3 | — | — | SUPERSEDED |
| ~~[MC-11](MC-11-macos-history-search.md)~~ | macOS History → **SUPERSEDED by [MC-R8](MC-R8-macos-history.md)** | 3 | — | — | SUPERSEDED |
| ~~[MC-12](MC-12-macos-shadowing.md)~~ | macOS Shadowing → **SUPERSEDED by [MC-R9](MC-R9-macos-shadowing.md)** | 4 | — | — | SUPERSEDED |
| ~~[MC-13](MC-13-audio-sync-optin.md)~~ | Opt-in audio sync → **SUPERSEDED by [MC-R10](MC-R10-audio-sync-optin.md)** | 4 | — | — | SUPERSEDED |

- **MC-M1 — Synced substrate:** MC-1..MC-4 (one model, one container; notes + profile sync Mac↔iOS).
- **MC-M2 — Coach on Mac:** MC-5, MC-6 (v2 engine replaces the one-shot popover).
- **MC-M3 — Companion window:** MC-7 (window shell ✅; surfaces moved to MC-R series).
- **MC-M4 — Loop + audio:** → MC-R9, MC-R10.

> **NOTE (2026-06-29):** MC-8..MC-13 were scoped against the pre-Phase-3 data model + IA. `origin/main`
> has since landed the Phase-3 Coach v2 refactor (DM-1 lean row + sidecar #92, HS-1/HS-2 History #91/#93,
> with DM-2 observation log + IA-1 Coach tab + PR-1 PracticeItem in flight), which reshapes both. The
> macOS surfaces are re-planned as the **MC-R series** below, re-founded on `origin/main`. MC-1..MC-7
> stay DONE on this branch; their *structure* carries forward (MC-1's sharing mechanism returns as
> MC-R2), only MC-1's old `TranscriptEntry` body is discarded. See
> [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md).

## macOS Companion — Phase-3 reconcile (MC-R series — supersedes MC-8..MC-13)

Re-found the macOS epic on `origin/main`'s Phase-3 model + IA. Decisions: re-found (not rebase); wait
for upstream DM-2 + PR-1 before re-founding the shared layer; macOS IA = Coach / History / Settings +
menu-bar capture + recents pane. Carry-forward legend: ✅ kept · ◐ re-applied on new base · ➕ new.
Design: [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md).

| ID | Title | Carry | Depends on | Size | Status |
|----|-------|-------|-----------|------|--------|
| [MC-R0](MC-R0-window-shell-carryforward.md) | Companion window shell (from MC-7) | ✅ | MC-R1 | S | IN-PROGRESS |
| [MC-R1](MC-R1-integrate-origin-main.md) | Integrate origin/main (re-found base) | ◐ | upstream DM-2 + PR-1 ✅ | L | DONE |
| [MC-R2](MC-R2-refound-shared-layer.md) | Re-found MC-1's shared layer on Phase-3 model | ✅ | MC-R1 | L | DONE |
| [MC-R3](MC-R3-macos-store-lean-windowed.md) | macOS store on lean row + windowed fetch (re-do MC-3) | ◐ | MC-R2 | M | DONE |
| [MC-R4](MC-R4-macos-coach-observation-log.md) | macOS Coach v2 on observation log (re-do MC-5 + MC-6) | ◐ | MC-R2, MC-R3 | L | DONE |
| [MC-R5](MC-R5-macos-coach-hub.md) | macOS Coach hub — Review feed + activation (was MC-8) | ◐ | MC-R0, MC-R4 | L | TODO |
| [MC-R6](MC-R6-macos-practice-surface.md) | macOS Practice surface (PR-2 on Mac) | ➕ | MC-R2, MC-R5 | M | TODO |
| [MC-R7](MC-R7-macos-progress.md) | macOS Progress — observation projections (was MC-10) | ◐ | MC-R4, MC-R0 | M | TODO |
| [MC-R8](MC-R8-macos-history.md) | macOS History — Notes\|Dictation + windowed (was MC-11) | ◐ | MC-R3, MC-R0 | S | TODO |
| [MC-R9](MC-R9-macos-shadowing.md) | macOS Shadowing (was MC-12) | ◐ | MC-R5, MC-R6 | M | TODO |
| [MC-R10](MC-R10-audio-sync-optin.md) | Opt-in audio sync (was MC-13) | ◐ | MC-R2, MC-R3 | M | TODO (device verify) |

- **MC-RM1 — Re-founded substrate:** MC-R1, MC-R2 (one shared synced model on the Phase-3 schema).
- **MC-RM2 — macOS engine + store:** MC-R3, MC-R4 (lean store + Coach v2 on the observation log).
- **MC-RM3 — Surfaces:** MC-R0, MC-R5, MC-R6, MC-R7, MC-R8 (Coach hub / Practice / Progress / History).
- **MC-RM4 — Loop + audio:** MC-R9, MC-R10.
