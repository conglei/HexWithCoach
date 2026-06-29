# macOS Companion v1 — bringing Coach v2 + synced Notebook to the Mac

**Status:** Design (2026-06-29)
**Decisions locked:** (1) macOS becomes a **full companion window** — Review / Notebook /
History / Progress / Shadowing in a real main window, menu bar stays quick-capture;
(2) sync scope = **notes + coach results + profile + audio** (audio opt-in) across Mac↔iOS.

## 1. Problem

iOS evolved into a spoken-English learning companion (Coach v2 two-lane engine, Review
feed, Shadowing, Progress, Notebook), all backed by a **SwiftData + CloudKit** store.
macOS is still the original menu-bar dictation tool: **TCA + flat-JSON local-only**
history and a **stateless one-shot** pronunciation popover. The two apps:

- use **different, incompatible note models** (`TranscriptEntry` @Model on iOS vs the
  `Transcript` struct on macOS), and
- only iOS persists to CloudKit,

so today **notes cannot sync** and **the iOS learning UI cannot be reused** on macOS.

The Coach *engine itself is already shared* — `VocoCore` holds the entire v2 pipeline
(LearnerProfile, FluencySignals, CoachPipeline, GOP, ShadowingScorer, ProgressSummary,
ObjectiveCardGenerator) and `VocoEngine` shares the ASR clients + Gemini adapter +
Keychain across both targets. **The gap is purely at the app-integration layer.**

Product note: macOS is arguably the *better* all-day capture surface (engineers dictate
into Slack/PRs/docs on the Mac all day), so the Mac should be a first-class capture +
review hub, not a stripped-down iOS port.

## 2. The linchpin: one synced model, one CloudKit container

Everything depends on the two apps sharing **one note schema pointed at one CloudKit
container**.

- **Move the SwiftData models out of the iOS target into the shared folder.**
  `TranscriptEntry` and `CoachCardEntity` live today in `Voco/TranscriptStore.swift`.
  Promote them into `VocoEngine/` (the Swift-5 synchronized group that already exists to
  share source across both targets — `VocoCore`'s strict concurrency makes SwiftData
  `@Model` awkward there, so `VocoEngine` is the right home, mirroring `GeminiCoachLLM`).
- **Shared `ModelContainer` factory** in `VocoEngine` (e.g. `SyncStore.swift`): builds the
  CloudKit-backed container, falls back to local-only when no iCloud account — exactly
  the iOS logic today, now used by both apps.
- **Shared explicit CloudKit container ID** added to *both* entitlements
  (`Voco/Voco.entitlements` and `VocoMac/VocoMac.entitlements`):
  `com.apple.developer.icloud-container-identifiers = iCloud.<shared-id>`,
  `com.apple.developer.icloud-services = CloudKit`. App Group ≠ CloudKit container — both
  apps must list the *same* CloudKit container for records to merge.
- **Conflict policy:** unchanged from iOS — last-writer-wins keyed by record `id`.

### Audio sync (opt-in)

Audio is currently loose files (App Group dir on iOS, App Support on macOS) referenced by
`audioFilename` — portable but **not synced**. To sync audio:

- Add `@Attribute(.externalStorage) var audioData: Data?` to `TranscriptEntry`. SwiftData
  stores it out-of-row and **CloudKit syncs it as a CKAsset automatically** — audio
  becomes part of the note record instead of a side file.
- **Keep the local file path for fast playback**; treat `audioData` as the sync carrier.
  Ingest flow: keyboard/recorder writes temp file → host ingests bytes into `audioData`.
- **Gate behind an opt-in toggle** (Settings, both platforms; off by default) per the
  prior P4-3 decision. Keyless objective analysis + LLM results already sync as JSON
  regardless, so coaching continuity does **not** require audio sync — audio sync is for
  cross-device *playback + pronunciation/shadowing review*.

### Profile must sync too

The LearnerProfile is the moat; it should follow the user across devices. Today
`LearnerProfileStore` / `CoachSnapshotLog` are file-JSON, **not synced**. Make them
CloudKit-synced — simplest path is a single-row SwiftData model (`LearnerProfileEntity`,
`CoachSnapshotEntity`) in `VocoEngine` wrapping the existing `Codable` payloads, so the
profile and growth history merge across Mac and iOS. (BYOK key stays **per-device** in the
Keychain — never synced, by design.)

## 3. macOS app architecture

Keep the existing **TCA shell** for the menu bar, hotkey, recording, and Settings — it
works and is well-tested. Do **not** force the new learning UI through TCA.

- **New main window** = standalone SwiftUI + SwiftData `@Query` + `@Observable` models,
  mirroring iOS (`NavigationSplitView`: Review · Notebook · History · Progress · Settings).
  This lets the macOS views reuse the iOS `@Observable` models directly.
- **Promote the per-app orchestrators into `VocoEngine`** now that they operate on shared
  models: `CoachService`, `CoachProgress`, `ShadowingModel`, `CoachPreferences`,
  `CapturePreferences`. Today these are iOS-target files; once the models are shared they
  are platform-agnostic and both apps use them.
- **Retire the old macOS Coach path:** `VocoMac/Features/Coach/*` (CoachFeature,
  CoachClient, Providers/, CoachModels, CoachFeedbackStore) → replaced by VocoCore's
  `CoachPipeline` + `CoachLLM`/`GeminiCoachLLM`. The menu-bar popover becomes a "latest
  insight" glance that deep-links into the Review window (or is dropped).
- **Migrate existing Mac history:** one-time read of `transcription_history.json` → insert
  as `TranscriptEntry(kind: .dictation)` into SwiftData, mark migrated, keep a backup.

Menu bar stays the zero-friction surface: hotkey capture, "Copy last transcript",
"Open Voco" (main window), Settings, Quit.

## 4. Phased plan / task breakdown (MC-*)

**Phase 1 — Unify model + sync (the linchpin)**
- MC-1  Move `TranscriptEntry` + `CoachCardEntity` into `VocoEngine`; shared `ModelContainer`
        factory; both targets compile against it.
- MC-2  Shared CloudKit container ID in both entitlements; verify Mac↔iOS record merge.
- MC-3  macOS: replace `FileStorage` history with the shared SwiftData store; JSON→SwiftData
        migration with backup.
- MC-4  Sync the profile: `LearnerProfileEntity` + `CoachSnapshotEntity` in `VocoEngine`.

**Phase 2 — macOS Coach v2 engine**
- MC-5  Promote `CoachService`/`CoachPreferences`/`CoachProgress` into `VocoEngine`; wire the
        two-lane pipeline on macOS (objective always-on at capture, LLM auto-batched + budget).
- MC-6  Remove the old macOS one-shot Coach (`Features/Coach/*`, `Providers/`).

**Phase 3 — macOS companion window**
- MC-7  New main window shell (NavigationSplitView, sidebar nav, native Mac layout).
- MC-8  Review feed (cards, "Got it"/"Not useful"/"Save", "Say it better").
- MC-9  Notebook capture (record-a-thought, saves as `TranscriptEntry(kind: .note)`).
- MC-10 Progress digest (per-lens deltas, streak, mastered patterns).
- MC-11 History as a search screen over the synced store.

**Phase 4 — Shadowing + audio sync**
- MC-12 Shadowing on macOS (TTS rewrite → record → GOP re-score), reuse `ShadowingModel`.
- MC-13 Opt-in audio sync via `@Attribute(.externalStorage)`; Settings toggle both platforms.

## 5. Risks / watch-items

- **CloudKit container shared across two bundle IDs** — supported within one dev team; both
  apps must list the identical container. Test the actual merge early (MC-2) before building on it.
- **TCA ↔ SwiftData coexistence on macOS** — isolate: TCA pipeline keeps its dependency
  clients; the new window is plain SwiftUI/@Observable over `@Query`. No bridging layer.
- **Migration correctness** — never drop Mac history; backup the JSON, make migration idempotent.
- **Audio over CloudKit** — short clips only; opt-in; watch CKAsset size + initial-sync cost.
- **Keychain per-device** — BYOK key does not sync, so users re-enter on each device (by design;
  surface this clearly in macOS Settings).
- **Two concurrent writers** — last-writer-wins per `id` (existing iOS policy); dedupe on `id`.

## 6. What is explicitly NOT changing

- The Coach v2 *engine* (`VocoCore`) — already shared and tested; we wire it, not rewrite it.
- ASR clients / `VocoEngine` transcription stack — already cross-platform.
- The macOS dictation/hotkey/paste pipeline (TCA) — stays as-is.
