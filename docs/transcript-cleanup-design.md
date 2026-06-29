# Transcript Cleanup — Design

**Status:** Draft / proposed
**Scope:** Shared deterministic + LLM transcript cleanup for VocoMac (macOS) and Voco
(iOS), including live-preview (streaming) behaviour, built on the current
SwiftData + CloudKit data layer.
**Owner:** TBD

> **Naming note (post-Voco rename).** Modules are `VocoCore` (pure SwiftPM),
> `VocoEngine` (shared engine folder), `VocoMac` (macOS app), `Voco` (iOS app),
> `VocoKeyboard` (keyboard extension). Some *type* names still carry the legacy `Hex`
> prefix (`HexAppGroup`, `HexSettings`) — those are real symbol names, kept verbatim.
> The App Group identifier is `group.co.stonefrontier.voco`.

---

## 1. Problem & goals

Raw ASR output (Whisper / Parakeet / Qwen3-ASR) contains disfluencies ("um", "uh",
false starts, duplicate words), spoken-form text that should be written-form
("twenty twenty-five" → 2025, "john at gmail dot com" → john@gmail.com), and
domain terms the recognizer spells/cases wrong ("voco with couch" → "Voco with Coach").

We want a **single, reusable cleanup module** that:

1. Runs the same way on **macOS** and **iOS** (one implementation, one set of tests).
2. Works **without a network** and on **all devices** (deterministic baseline), with an
   **optional on-device LLM tier** for grammar/paragraphing where available.
3. Behaves correctly under **live preview / streaming**, where partial text is still
   being revised, without causing cursor flicker.
4. Treats the user's **domain vocabulary as one list** that powers deterministic
   replacement, recognizer biasing, and the LLM glossary — and **syncs across the
   user's devices** on the existing CloudKit rails.

### Non-goals

- Replacing the ASR models or their decoding.
- Cloud cleanup (the existing `GeminiClient` coach path is separate).
- Shipping a bundled LLM (model selection is deferred — see §9, Phase 3).

---

## 2. Current data architecture (what we build on)

The data layer changed substantially: **iOS now persists via SwiftData with automatic
CloudKit sync.** This is the established cross-device mechanism and the cleanup config
must ride on it rather than invent its own.

`Voco/TranscriptStore.swift`:

- `@Model TranscriptEntry` — the unified note/dictation record (id, text, date,
  `kindRaw`, `sourceAppName`, `audioFilename`, `coachAnalyzedAt`, `objectiveAnalyzedAt`,
  `wordTimingsJSON`, `pronunciationJSON`).
- `@Model CoachCardEntity` — a SwiftData **mirror** of the pure `CoachCard` (VocoCore),
  so the Review feed can `@Query` it and it syncs. **This mirror pattern is the
  template the cleanup vocabulary should follow.**
- `TranscriptStore.makeContainer()` builds a `ModelContainer` with
  `ModelConfiguration(cloudKitDatabase: .automatic)`, **falling back** to local-only
  (`.none`) then in-memory when iCloud is unavailable.
- Sync is **user-toggleable**: `SyncPreferences.iCloudEnabled` (default true), stored in
  the App Group, read once at launch to choose the configuration.
- `iOS DictationModel` holds a `ModelContext`, builds `TranscriptEntry(text:…)` and
  `insert`/`save`s it — **this is the cleanup insertion point on iOS.**

### CloudKit-imposed schema constraints (learned from `TranscriptEntry`)

Any new synced `@Model` must obey these — they shape the vocabulary schema in §4:

1. **Every attribute needs a default value.**
2. **No unique constraints** (CloudKit forbids them) → carry a stable `UUID` and dedup
   in code (`TranscriptStore.ensureUniqueIDs` is the existing precedent).
3. **Complex/Codable values are JSON-encoded into `String` fields** (`wordTimingsJSON`,
   `pronunciationJSON`) so CloudKit can sync them.
4. **Relationships must be optional.**

### The two asymmetries that define the work

| | iOS (`Voco`) | macOS (`VocoMac`) | Keyboard (`VocoKeyboard`) |
|---|---|---|---|
| Store | **SwiftData + CloudKit** | **TCA `@Shared(.fileStorage)`** (`hex_settings.json`), no SwiftData/CloudKit | **App Group IPC only** (`HexAppGroup`, `KeyboardIPC`) — no SwiftData |
| `@Model` types | defined here, in the **app target** | absent | absent |
| Cleanup today | none | `WordRemoval`→`WordRemapping` at `TranscriptionFeature.swift:835` | none |

So "reuse for both platforms + sync" now has two concrete obstacles:
**(a)** the `@Model` types live in the iOS app target, not a shared module; and
**(b)** the keyboard extension cannot open a CloudKit SwiftData store.

---

## 3. What already exists (reuse, don't rebuild)

| Capability | Where | Notes |
|---|---|---|
| Vocabulary dictionary (`match → replacement`, toggle, word-boundary, case-insensitive) | `VocoCore/Models/WordRemapping.swift` | This **is** the custom-vocab value type. |
| Filler removal (regex patterns + whitespace/punct cleanup) | `VocoCore/Models/WordRemoval.swift` | Defaults: `uh+ um+ er+ hm+`. |
| Pure↔`@Model` mirror pattern | `CoachCard` (VocoCore) ↔ `CoachCardEntity` (`Voco`) | Template for the vocab entity. |
| macOS settings/lists | `VocoCore/Settings/HexSettings.swift`, `@Shared(.hexSettings)` | macOS-only loader; file-backed. |
| macOS apply (filler → remap) | `VocoMac/Features/Transcription/TranscriptionFeature.swift:835` | Hand-rolled inline order. |
| Live preview (streaming + snapshot) | `VocoMac/Features/Transcription/TranscriptionFeature.swift`, `VocoCore/Logic/LiveTextInsertion.swift` | macOS-only; Parakeet-gated. |
| Confirmed/volatile boundary | `VocoEngine/LiveTranscriptionClient.swift` (`isConfirmed`, `confirmedTranscript`, `volatileTranscript`) | The seam streaming cleanup needs. |
| Flicker control | `LivePreviewUpdateGate`, `LiveTextInsertionLogic.keystrokeUpdateAction`, `LivePreviewTranscriptionScheduler` | Cleanup must not break these. |
| App Group container (audio, prefs, IPC) | `HexAppGroup.identifier = group.co.stonefrontier.voco` | `AudioStore`, `SyncPreferences`, `KeyboardIPC`. |
| Recognizer context hooks (unused) | `VocoEngine/QwenClient.swift` (`generate`), Whisper `DecodingOptions.promptTokens` | Glossary biasing, not yet wired. |

**Gaps this design closes:** iOS applies no cleanup; macOS logic is inline/untestable;
the glossary feeds nothing; no ITN/formatting stages; the vocab list doesn't sync.

---

## 4. Architecture overview

```
ASR (raw)
   │
   ▼
┌──────────────────────────── CleanupPipeline (VocoCore, pure) ──────────────────────────┐
│  [1] filler removal     (WordRemoval)          streamingSafe: YES                        │
│  [2] ITN / formatting   (numbers, emails, ...)  streamingSafe: YES (confirmed-prefix)    │
│  [3] vocabulary remap   (WordRemapping)         streamingSafe: YES (runs late -> wins)   │
│  [4] LLM grammar tier   (Foundation Models /    streamingSafe: NO  (FINALIZATION ONLY)   │
│                          bundled Qwen, opt-in)                                            │
└──────────────────────────────────────────────────────────────────────────────────────────┘
   │                                   ▲
   ▼                                   │  glossary = enabled WordRemapping.replacement
final / inserted text                  └── also fed to: Qwen3-ASR context, Whisper promptTokens
```

Two principles:

- **Determinism downstream, recognizer-bias upstream.** The deterministic stages are the
  reliable, model-independent baseline; recognizer biasing (Qwen context, Whisper prompt)
  is an optional boost fed from the *same* glossary.
- **Cheap & deterministic on the live path; expensive & destructive only at finalize**
  (§6).

---

## 5. The reusable module

### 5.1 Placement

All cleanup **logic** lives in **VocoCore** (`VocoCore/Sources/VocoCore/Cleanup/`) — the
pure package imported by every target and the only layer the fast `swift test` runner
covers.

```
VocoCore/Sources/VocoCore/Cleanup/
  CleanupConfig.swift        // pure value type the pipeline consumes
  CleanupStage.swift         // stage protocol + streamingSafe contract
  CleanupPipeline.swift      // applyFinal / applyLive — pure functions
  Stages/ FillerRemovalStage.swift, VocabRemapStage.swift, ITN/...
  Glossary.swift             // derive glossary; format for LLM / ASR context
```

`CleanupConfig` is a **pure value type** assembled from persisted data — it does not know
about SwiftData, CloudKit, files, or App Groups:

```swift
public struct CleanupConfig: Equatable, Sendable {
    public var fillerRemovalEnabled: Bool
    public var fillerRemovals: [WordRemoval]   // reuse existing value type
    public var vocabulary: [WordRemapping]     // reuse existing value type (== glossary source)
    public var formatting: FormattingOptions   // Phase 2 ITN toggles
    public var llmGrammar: LLMGrammarOptions    // Phase 3
}
```

### 5.2 Persistence & cross-device sync — ride the existing CloudKit store

The earlier App-Group + `NSUbiquitousKeyValueStore` design is **dropped**: the codebase
already has SwiftData + CloudKit, which owns local persistence, cross-device sync, and
conflict resolution. The vocabulary follows the **`CoachCard` ↔ `CoachCardEntity`** mirror
pattern exactly.

```
              ┌──────────────── CloudKit (automatic, cross-device) ────────────────┐
              │     ModelConfiguration(cloudKitDatabase: .automatic)                │
              └───────▲──────────────────────────────────────────────▲─────────────┘
                      │ SwiftData                                     │ SwiftData
        VocoMac app ──┤  VocabularyEntity / CleanupSettingsEntity     ├── Voco (iOS) app
        (must adopt)  │  (shared @Model in VocoCore)                  │  (already on store)
                      └───────────────────────────────────────────────┘
                                          │ host app projects compact glossary
                                          ▼
                              App Group  ── read-only ──  VocoKeyboard extension
```

- **Source of truth + sync:** a SwiftData `@Model` (e.g. `VocabularyEntity`, and a small
  `CleanupSettingsEntity` for the toggles) in the **CloudKit-backed `ModelContainer`**,
  mirroring the pure `WordRemapping`/`WordRemoval`/`CleanupConfig` value types. CloudKit
  handles Mac ↔ iPhone sync automatically — **no custom merge code** (contrast the prior
  KVS design). Apply the §2 CloudKit constraints: defaults on every field, stable `UUID`
  + dedup, no unique constraints.
- **Keyboard projection:** the extension can't open the CloudKit store, so the **host app
  projects a compact glossary + deterministic rule config into the App Group**
  (`UserDefaults(suiteName:)` / a small JSON file), refreshed on change — exactly how
  `AudioStore` and `KeyboardIPC` already use the App Group. The keyboard reads that
  projection only.
- **macOS adoption (the central reuse work):** `VocoMac` is still on TCA file-storage and
  has no SwiftData/CloudKit. For Mac ↔ iPhone vocab sync, **the `@Model` types must move
  out of the iOS app target into VocoCore** (so both apps share them), and `VocoMac` must
  open the same CloudKit `ModelContainer`. Until that lands, macOS cleanup config stays in
  `HexSettings` (device-local, unsynced) behind the same `CleanupConfig` interface.

> The pipeline only ever sees `CleanupConfig`; a thin per-platform adapter builds it from
> SwiftData (iOS, future macOS), the App-Group projection (keyboard), or `HexSettings`
> (interim macOS). That adapter boundary is what keeps the logic shared.

### 5.3 `CleanupStage` — the streaming contract

```swift
public protocol CleanupStage: Sendable {
    var id: String { get }
    var streamingSafe: Bool { get }                                  // safe on still-revising text
    func apply(_ text: String, config: CleanupConfig) -> String
}
```

Every live-path stage MUST be **deterministic, idempotent, and monotonic on the confirmed
prefix** — otherwise the prefix-diffing in `keystrokeUpdateAction` / `LivePreviewUpdateGate`
collapses into full backspace-and-retype (max flicker). This is the single most important
constraint in the design.

### 5.4 `CleanupPipeline` — two entry points

```swift
public enum CleanupPipeline {
    /// Full pipeline incl. optional LLM tier. Finalized text + iOS clips.
    public static func applyFinal(_ raw: String, config: CleanupConfig,
                                  llm: CleanupLLM? = nil) async -> String

    /// Deterministic, streamingSafe stages only; cleans the confirmed prefix.
    public static func applyLive(confirmed: String, volatile: String,
                                 config: CleanupConfig) -> (cleanedConfirmed: String, tail: String)
}
```

`CleanupLLM` is injected (mirrors the existing `CoachLLM` protocol) so it stubs in tests.

### 5.5 Glossary reuse

```swift
public enum Glossary {
    public static func terms(from config: CleanupConfig) -> [String] {
        config.vocabulary.filter(\.isEnabled).map(\.replacement)
    }
}
```

One synced user list → three consumers: deterministic replace (stage 3), **Qwen3-ASR**
context (`VocoEngine/QwenClient.swift`, currently passes none), **Whisper**
`DecodingOptions.promptTokens` (plumbing already threaded).

### 5.6 Raw vs. cleaned and the `TranscriptEntry` schema

`TranscriptEntry` stores a single `text`. The Coach pipeline *wants* disfluencies, but the
inserted/displayed text should be cleaned. Decide one of:

- **(A)** store **raw** in `text` (Coach analyzes it), clean only at insertion/display; or
- **(B)** add a `cleanedText` (or `rawText`) field to `TranscriptEntry` so both persist.

Proposed: **(A)** for Phase 1 (no schema change; cleanup is a presentation/insertion
transform), revisit (B) if Coach and display need to diverge persistently. Any new field
must follow the §2 CloudKit constraints.

---

## 6. Stage catalog

| # | Stage | Type | streamingSafe | Phase |
|---|---|---|---|---|
| 1 | Filler removal | regex (`WordRemoval`) | YES (confirmed-prefix) | 1 (exists) |
| 3 | Vocabulary remap | regex (`WordRemapping`) | YES (confirmed-prefix) | 1 (exists) |
| 2a | Number / date ITN | rule | YES (once span confirmed) | 2 |
| 2b | Email / URL formatting | rule | YES | 2 |
| 2c | Acronyms / brackets / currency | rule + lexicon | YES | 2 |
| 2d | Smart capitalization | rule + NLP | hybrid | 2 |
| 2e | Ending punctuation / trailing space | rule | YES | 2 |
| 4 | Grammar / paragraphing | LLM | NO (finalize only) | 3 |

---

## 7. Live preview / streaming (macOS)

The confirmed/volatile zone model (already supported by `LiveTranscriptionUpdate`):

- **Volatile tail:** show ~raw (whitespace tidy). Last few words are rough by design.
- **Confirmed prefix:** run `applyLive` (deterministic stages). Stable, so cleaning it
  won't fight the next ASR revision.
- **Finalize (`finish()`):** run `applyFinal`, including the LLM tier.

Ordering (cleanup inserted upstream of the existing flicker machinery):

```
ASR update → applyLive(confirmed,volatile) → LivePreviewUpdateGate.shouldApply
           → LiveTextInsertionLogic.keystrokeUpdateAction → insert at cursor
```

**Display == final:** confirmed-prefix cleanup output should equal what's ultimately
inserted, so finalization's LLM only *adds* (grammar/paragraphs) and never re-does
deterministic work the user already watched stream in (avoids a jarring "snap").

iOS has **no** streaming preview (`DictationModel` transcribes whole clips and inserts a
`TranscriptEntry`), so iOS only ever calls `applyFinal`. `applyLive` is only needed if
streaming is later added to the keyboard (where the extension memory limit, not cleanup
cost, is the real constraint).

---

## 8. Platform wiring

| | macOS (`VocoMac`) | iOS app (`Voco`) | iOS keyboard (`VocoKeyboard`) |
|---|---|---|---|
| Config source | `HexSettings` now → shared CloudKit `@Model` after macOS adoption | SwiftData (CloudKit) | App Group projection (read-only) |
| Live path | `applyLive` on confirmed prefix | n/a (no streaming) | n/a |
| Final path | `applyFinal` replaces inline block at `TranscriptionFeature.swift:835` | `applyFinal` in `DictationModel` before building `TranscriptEntry` | `applyFinal` (deterministic only; LLM gated by memory) |
| LLM tier | Foundation Models / bundled (Phase 3) | same | likely **off** in extension (memory) |

---

## 9. Testing

- All stages + `applyFinal`/`applyLive` are pure → **VocoCore `swift test`**. Cover stage
  ordering, idempotency, monotonicity on growing confirmed prefixes, glossary derivation,
  and golden messy-dictation → expected-clean fixtures.
- `CleanupLLM` is injected and stubbed (no network), like `CoachLLM`.
- SwiftData mirroring (`WordRemapping` ↔ `VocabularyEntity`) + the App-Group projection
  covered in `VocoTests` / `VocoMacTests`; keep CloudKit out of unit tests (use
  `cloudKitDatabase: .none` / in-memory containers).

---

## 10. Phasing

- **Phase 0 — shared synced vocab store (infra).** Move the `@Model` types (or at least the
  new `VocabularyEntity`/`CleanupSettingsEntity`) into **VocoCore**; have `Voco` use them in
  the existing CloudKit container; write the **App-Group glossary projection** for the
  keyboard. Adopt the SwiftData + CloudKit store in **`VocoMac`** (entitlements §10.1) so the
  vocab list syncs Mac ↔ iPhone. **No cleanup behaviour yet** — prove "edit glossary on Mac
  → appears on iPhone, and reaches the keyboard projection."
- **Phase 1 — unify + reach iOS (mostly reuse).** Extract `CleanupConfig`, `CleanupStage`,
  `CleanupPipeline` (both entry points). Wrap the existing `WordRemoval`/`WordRemapping`
  appliers as stages. Point macOS at `applyFinal`/`applyLive`; add `applyFinal` to iOS
  `DictationModel` before `TranscriptEntry` insert. Derive the glossary and thread it into
  Qwen/Whisper context. No new models.
- **Phase 2 — ITN/formatting stages.** Add §6 rule stages; each declares its zone; optional
  per-stage UI toggles.
- **Phase 3 — LLM grammar tier.** Implement `CleanupLLM` (Apple Foundation Models vs bundled
  Qwen — separate decision), finalization-only, conservative, opt-in for live mode.

### 10.1 Entitlement & release impact (Phase 0)

- **`VocoMac`:** has **no** App Group or iCloud today
  ([VocoMac/VocoMac.entitlements](../VocoMac/VocoMac.entitlements)). To join the synced store
  it needs **App Group** + **CloudKit / iCloud** entitlements (`com.apple.developer.icloud-*`,
  `com.apple.security.application-groups`). macOS App Group ids conventionally need the
  **team-id prefix**, differing from iOS's bare value → `HexAppGroup.identifier` becomes
  **platform-conditional**.
- **`Voco`:** already on the CloudKit store; no change.
- **`VocoKeyboard`:** App Group only; no change.
- **Release pipeline:** `VocoMac` is Developer-ID + sandboxed + notarized; adding iCloud
  changes provisioning/signing — validate an archive/notarize run before relying on it.
  Reuse the established **graceful fallback** (`cloudKitDatabase: .automatic` → `.none` →
  in-memory) and **user toggle** (`SyncPreferences.iCloudEnabled`).

---

## 11. Open questions / decisions

1. **Vocab persistence — DECIDED:** ride the existing **SwiftData + CloudKit** store
   (cross-device sync, no custom merge), mirroring `CoachCard` ↔ `CoachCardEntity`.
   (Superseded: the App-Group + `NSUbiquitousKeyValueStore` design — dropped now that the
   codebase has CloudKit.)
2. **Where do the `@Model` types live?** Currently the iOS **app target**. Proposed: move
   shared entities (incl. the new `VocabularyEntity`) into **VocoCore** so `VocoMac` can use
   them. Confirm VocoCore taking a `SwiftData` dependency is acceptable.
3. **Vocabulary == remapping?** Keep unified (a vocab entry is a `WordRemapping` whose
   `replacement` is the canonical term) vs a distinct `VocabularyEntry`. Proposed: keep
   unified to avoid duplicate concepts.
4. **Raw vs cleaned on `TranscriptEntry`:** transform-at-insertion (A, proposed) vs persist
   both via a new field (B). See §5.6.
5. **macOS SwiftData adoption scope:** adopt only the vocab/cleanup entities now, or migrate
   `HexSettings` wholesale onto SwiftData later. Proposed: vocab/cleanup only for Phase 0.
6. **Keyboard LLM tier:** almost certainly off in-extension (memory); run in host app or
   skip. Confirm the extension budget.
