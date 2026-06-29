# macOS Companion ↔ Phase-3 Coach refactor — reconciliation design

**Status:** Design (2026-06-29)
**Supersedes parts of** [macos-companion-v1-design.md](macos-companion-v1-design.md) (the data-model
and IA sections) in light of the Phase-3 Coach v2 refactor now landing on `origin/main`.

## 1. What happened

My macOS Companion epic (MC-1…MC-7, on `claude/focused-proskuriakova-e8436e`) and the Phase-3
Coach v2 refactor (on `origin/main`, #81–#93) independently refactored the same data model and IA:

| | My epic (this branch) | origin/main Phase-3 |
|---|---|---|
| `TranscriptEntry` | old inline-blob row, **moved to `VocoEngine`** (shared) | **lean row + `TranscriptAnalysis` sidecar** (DM-1 #92), still in `Voco/` (iOS-only) |
| Coaching evidence | curated `CoachCardEntity` only | **`CoachObservation` append-only log** (DM-2, pending); cards/profile/trends = projections |
| History | mirror-projection bridge (MC-3) | **Notes\|Dictation segment** (HS-1 #91) + **windowed fetch** (HS-2 #93) |
| IA | sidebar Review/Notebook/History/Progress (MC-7) | **Home / History / Coach / Settings**; Review+Practice merge into **Coach** (IA-1, pending) |
| Practice | n/a | separate synced **`PracticeItem`** model (PR-1, pending) |

Branch state: **+21 / −14** vs `origin/main`. The `TranscriptEntry` divergence alone is a hard
conflict (same `@Model`, different shape, different file, different module).

## 2. Decision: main's Phase-3 is the source of truth; my epic re-founds on top of it

Do **not** fight upstream. `origin/main` owns the data-model + iOS-coach evolution. My epic owns a
**different, complementary** concern: *make that model cross-platform + CloudKit-synced, and build the
macOS surfaces.* Reconciliation = **fold my "share it" idea into main's Phase-3 model**, not preserve
my specific MC-1 schema.

Concretely:
- **Discard MC-1's frozen schema.** Adopt main's lean `TranscriptEntry` + `TranscriptAnalysis`
  sidecar + (when it lands) `CoachObservation` + `PracticeItem` as the canonical types.
- **Re-found the shared layer (a new "MC-1′").** Move main's Phase-3 `@Model` types into the shared
  `VocoEngine` layer and register them in the shared `SyncStore.makeContainer()` so **both** apps
  compile the same schema and it syncs via the one CloudKit container (the still-valid core of MC-1/MC-2).
  This is effectively "DM-1/DM-2/PR-1, but cross-platform + synced."
- **Keep what survives from my epic:** MC-2 (shared CloudKit container + entitlements), the macOS
  store-bridge *pattern* (MC-3) re-expressed against the lean row + windowed fetch, MC-5's
  shared-`CoachService`-in-`VocoEngine` approach re-applied on top of main's evolved `CoachService`,
  MC-6's legacy-Coach removal, and MC-7's window shell (re-sectioned to the new IA).

## 3. Sequencing: let the iOS model settle, then re-found once

The Phase-3 model is **mid-flight**: DM-1/HS-1/HS-2 merged, but **DM-2 (observation log)** and
**PR-1 (PracticeItem)** — the remaining *schema-defining* pieces — are not. Re-founding the shared
layer now would capture DM-1 but miss DM-2/PR-1 and force a second re-found.

**Therefore:**
1. **Pause net-new macOS feature work** (MC-8…MC-13 as previously scoped — they're invalid).
2. **Let the schema-defining iOS Phase-3 tasks land on `origin/main`** — at minimum **DM-2**
   (observation log) and **PR-1** (PracticeItem). IA-1/PR-2/PR-3 are UI and can trail.
3. **Re-found the cross-platform layer once** against the settled model (the new linchpin below).
4. **Then build the macOS surfaces** against the new model + new IA.

This trades a little calendar time for doing the painful shared-schema move exactly once.

## 4. Revised cross-platform data layer (the new linchpin)

Shared in `VocoEngine`, registered in `SyncStore.makeContainer()`, synced via CloudKit on both apps:

- `TranscriptEntry` (lean) — `pronunciationSummaryJSON` on-row + faulted `analysis` relationship; `#Index` on `date`/`kindRaw`.
- `TranscriptAnalysis` (heavy sidecar) — `wordTimingsJSON`, `pronunciationJSON`.
- `CoachObservation` (append-only dated findings) — the durable substrate; **macOS Review + Progress read projections of this**, not just curated cards.
- `PracticeItem` (separate synced model) — never in History queries.
- Plus the already-shared `CoachCardEntity`, `LearnerProfileEntity`, `CoachSnapshotEntity` (MC-4), re-expressed as projections of the observation log where the plan says so.

**Caveat to carry upstream:** the Phase-3 plan is written iOS-only ("register in `ContentView`,
`OnboardingView`, `VocoTests`"). The cross-platform version registers in the **shared**
`SyncStore.makeContainer()` instead, plus the macOS in-memory/test containers. Same types, one
registration point per platform.

## 5. Revised macOS IA (replaces MC-7's section set)

Mirror IA-1, adapted to the Mac (capture is the always-on menu-bar hotkey, not a tab):

- **Coach** (primary) — Review feed (card/observation projections) + Practice (drills + paste +
  phrasebook) + Progress digest. Mirrors iOS's merged Coach hub and the #81–#87 concepts
  (interactive pronunciation sounds, severity-ranked "sounds to work on", calm note view + selective
  coloring, "what an unclear sound came out as").
- **History** — Notes\|Dictation segment (HS-1) + windowed fetch (HS-2) over the lean row.
- **Settings** — existing + `CoachV2SettingsView` (BYOK/opt-in/budget, from MC-5).
- **Capture** stays the always-on menu-bar hotkey, **plus a small recents / quick-note pane** in the
  window (decision 2026-06-29) — leaning into "macOS = all-day capture hub." No separate "Home" tab.

MC-7's placeholder views (`MacReviewView`/`MacNotebookView`/`MacHistoryView`/`MacProgressView`) are
re-cut into `MacCoachView` (hub) + `MacHistoryView` (segmented/windowed) + Settings.

## 6. Revised macOS backlog (supersedes MC-8…MC-13)

**Nothing structural from MC-1…MC-7 is thrown away.** The only genuinely-discarded piece is the *old
field layout* of `TranscriptEntry` that MC-1 froze (superseded by DM-1's lean+sidecar — it would have
changed regardless). Every MC-R task is annotated with what it **carries forward** (✅), **re-applies
on the new base** (◐), or **builds new** (➕).

- **MC-R1 — Integrate `origin/main` (re-found base).** ◐ Take `origin/main` as the base; re-apply the
  still-valid macOS deltas, resolving `TranscriptEntry`/`CoachService`/History conflicts by **adopting
  main's versions**. Output: branch builds on the new model, iOS unchanged. *(Was: the implicit base
  of the whole epic.)*
- **MC-R2 — Re-found MC-1's shared layer on the Phase-3 model.** ✅ **This IS MC-1, brought back.**
  Re-use MC-1's exact mechanism (`@Model` types + `SyncStore.makeContainer()` + `SyncPreferences` in
  `VocoEngine`, synced via the one CloudKit container) — now wrapping main's **lean `TranscriptEntry` +
  `TranscriptAnalysis` + `CoachObservation` + `PracticeItem`** instead of the old inline-blob row.
  Carries forward verbatim: **MC-2** (container + entitlements + explicit pin), **MC-4** (profile/snapshot
  entities — possibly re-expressed as observation-log projections), the duration/sourceApp fields.
  *Re-does only:* the model body (adopt main's shape) and the container registration. **New linchpin.**
- **MC-R3 — macOS store on the lean row + windowed fetch.** ◐ Re-apply **MC-3**'s store-bridge pattern
  against DM-1's lean row + HS-1/HS-2 (Notes\|Dictation segment + windowed/paginated fetch).
- **MC-R4 — macOS Coach v2 on the observation log.** ◐ Re-apply **MC-5**'s "shared `CoachService` in
  `VocoEngine`" approach on top of main's *evolved* `CoachService` + the DM-2 observation log. (The
  biggest re-apply — main reworked iOS `CoachService` in #81–#89.) Carries **MC-6** (legacy macOS coach
  removal — still needed; main's macOS app still has the old one-shot coach).
- **MC-R5 — macOS Coach hub** (Review feed + activation). ➕/◐ Re-cut **MC-7**'s `MacReviewView` into a
  `MacCoachView` hub reading observation/card projections; mirror #81–#87 (interactive sounds,
  severity-ranked "sounds to work on", calm note view, "what an unclear sound came out as").
- **MC-R6 — macOS Practice surface** (drills + paste + phrasebook). ➕ PR-2 on the Mac, over the shared
  `PracticeItem`.
- **MC-R7 — macOS Progress** (projections of the observation log). ◐ Was MC-10; now reads `CoachObservation`.
- **MC-R8 — macOS History** (Notes\|Dictation + windowed). ◐ Was MC-11; aligns to HS-1/HS-2.
- **MC-R9 — Shadowing on macOS.** ◐ Was MC-12. **MC-R10 — opt-in audio sync.** ◐ Was MC-13.
- **MC-R0 — Window shell.** ✅ **MC-7 carries forward** (window/menu/activation + `ModelContainer` in
  the environment); only the section set is re-cut (Coach / History / Settings + recents pane).
- Device-verify gates unchanged: the live CloudKit merge (MC-2/MC-R2) and audio sync (MC-R10).

## 7. Decisions (resolved 2026-06-29)

1. **Reconcile strategy → re-found on `origin/main`.** Take `origin/main` as base and re-apply only the
   still-valid macOS deltas on the new model. MC-1's *mechanism* returns (MC-R2); its old schema body is
   dropped. (Chosen over a tangled 21-commit rebase.)
2. **Sequencing → wait for DM-2 + PR-1.** Let the remaining schema-defining iOS tasks (observation log,
   PracticeItem) land on `origin/main` first, then re-found the shared layer **once**. No second move.
3. **macOS capture → menu-bar hotkey + a recents/quick-note pane** in the window. Sidebar =
   Coach / History / Settings. No literal Home tab.
4. **Ownership → my epic re-founds the model in `VocoEngine`** (cross-platform owner). The iOS Phase-3
   tasks define the *shape*; MC-R2 promotes the settled shape to the shared layer and keeps iOS green.

## 8. Process note (so this doesn't recur)

The divergence was avoidable: this epic ran 21 commits without re-syncing to `origin/main` (I tracked a
stale local `main` ref). Going forward, **re-fetch `origin/main` before each wave** and rebase early
when upstream is hot. The "wait for DM-2/PR-1 then re-found" plan bakes this re-sync in.
