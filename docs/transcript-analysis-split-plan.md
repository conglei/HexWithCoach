# Transcript & Coaching Data Model (greenfield design)

Status: proposed
Scope: iOS app target (`Voco/`), shared Coach engine (`VocoCore/`)
Related: History scaling (windowed fetch + delete), `coach-engine-deep-design.md`,
`review-coach-companion-design.md`

## Context

This is a **new app with no shipped users**, so there is **no backfill and no
migration** — we design the schema correctly once. (Forward schema evolution after v1
still needs the usual additive-compatibility care under CloudKit, but that's normal
versioning, not a v1 concern.)

Two product decisions shape the model:

- **Coaching is opt-in.** A user must enable it. Notes captured while coaching is off
  have no analysis and no coaching observations. Every coaching field is therefore
  optional, and the schema must read perfectly fine with all of it absent.
- **Coaching is likely a paid feature later** (possibly moving off BYOK to a
  server-backed key). *Deferred* — but the data model stays payment-agnostic: nothing
  about how analysis is paid for or authorized belongs in these tables. Tag findings by
  `origin`/`lens`, not by key source.

## Three storage tiers, by access pattern

The whole design is one idea: **separate data by how it's read.**

1. **Lean row** (`TranscriptEntry`) — what the History list and corpus analytics scan.
2. **Heavy sidecar** (`TranscriptAnalysis`) — bulky raw artifacts, faulted only in detail.
3. **Observation log** (`CoachObservation`) — granular, dated coaching findings; the
   durable analytics substrate. Profile, Review cards, trends, and dashboards are
   **derived projections** of it.

### Tier 1 — `TranscriptEntry` (lean, list-bearing, synced)

```swift
@Model
final class TranscriptEntry {
    var id: UUID = UUID()
    var text: String = ""
    var date: Date = Date()
    var kindRaw: String = TranscriptKind.note.rawValue   // note | dictation
    var sourceAppName: String?
    var audioFilename: String?
    var coachAnalyzedAt: Date?       // LLM lane ran
    var objectiveAnalyzedAt: Date?   // objective lane ran
    var pronunciationSummaryJSON: String?  // compact PronunciationSignals (~1 KB)
    @Relationship(deleteRule: .cascade, inverse: \TranscriptAnalysis.entry)
    var analysis: TranscriptAnalysis?
}
```

Add `#Index` on `date` and `kindRaw` (iOS 18) — the History query is sorted by date and
segmented by kind. The compact pronunciation summary lives here (not the sidecar) so
corpus analytics never fault the heavy blob.

### Tier 2 — `TranscriptAnalysis` (heavy, faulted lazily, synced)

```swift
@Model
final class TranscriptAnalysis {
    var id: UUID = UUID()
    var wordTimingsJSON: String?     // [WordTiming]
    var pronunciationJSON: String?   // full PronunciationResult (per-word × per-phoneme)
    var entry: TranscriptEntry?
    init() {}
}
```

A SwiftData to-one relationship is faulted: fetching a `TranscriptEntry` does **not** load
its analysis until `entry.analysis` is accessed. The History list and corpus scans never
touch it.

### Tier 3 — `CoachObservation` (append-only dated findings, synced)

The durable spine for **cross-note coaching**. One row per finding, written at analysis
time, never mutated:

```swift
@Model
final class CoachObservation {
    var id: UUID = UUID()
    var noteID: UUID = UUID()       // source transcript
    var date: Date = Date()         // note capture date (so trends bucket by speaking day)
    var lensRaw: String = ""        // grammar | lexis | discourse | pronunciation | prosody
    var originRaw: String = ""      // objective | llm
    var patternKey: String?         // canonical dedupe key (e.g. "drop-articles-abstract-nouns")
    var word: String?               // for word-level findings (pronunciation)
    var gop: Double?                // pronunciation goodness, when applicable
    var severity: Int = 0
    var span: String?               // user's exact words (privacy: .private at log sites)
    init() {}
}
```

Why this exists: today `CoachInsight` is a transient struct — `CoachCardCurator` collapses
insights to **one card per pattern key** and only the curated `CoachCardEntity` is
persisted, so the granular evidence is discarded. That makes occurrence-level coaching
("dropped articles 7× across 5 notes", "is this pattern regressing?", "show every time I
did this", per-word GOP over weeks) impossible after the fact. Persisting observations
makes all of those a query, and means new coaching features are new queries — not new
tables.

Note: per-word pronunciation trends need **no separate snapshot** — they're just
`CoachObservation` rows with `lens == .pronunciation` and a `word`/`gop`. `CoachSnapshot`
can stay as a fast pre-rolled per-note scalar, or itself become a projection of the log.

## Accessor design

Call sites read through computed properties on `TranscriptEntry`; keep them, backed by the
right tier:

```swift
extension TranscriptEntry {
    var wordTimings: [WordTiming]? {            // heavy → sidecar (lazy)
        get { analysis?.wordTimings }
        set { ensureAnalysis().wordTimings = newValue }
    }
    var pronunciationResult: PronunciationResult? {   // heavy → sidecar (lazy)
        get { analysis?.pronunciationResult }
        set {
            ensureAnalysis().pronunciationResult = newValue
            pronunciationSummaryJSON = newValue
                .map { PronunciationSignals(result: $0) } /* encode → */
        }
    }
    var pronunciationSignals: PronunciationSignals? { /* decode summary (cheap, on-row) */ }

    private func ensureAnalysis() -> TranscriptAnalysis {
        if let a = analysis { return a }
        let a = TranscriptAnalysis(); a.entry = self; analysis = a; return a
    }
}
```

Writers: `DictationModel.swift:113` (`wordTimings`, capture) and `CoachService.swift:389`
(`pronunciationResult`, objective lane) — both go through the sidecar via the setter.
The objective/LLM lanes additionally append `CoachObservation` rows for each finding at
the same point they produce insights (`CoachService` around 269/337/358), instead of only
curating cards. `CoachCardCurator` then curates **from the persisted observations**, and
`LearnerProfile` becomes a projection rebuilt from them.

Readers are unchanged: `CoachService` (analysis path), `TranscriptDetailView` (detail) fault
the sidecar only for the note in hand; `ProgressDigestView.swift:59` reads the cheap on-row
summary; cross-note trends query `CoachObservation`.

### Write sites (sketch)

Today insights are produced and then **discarded** at curation (`CoachService.swift:268-270`
single-note, `:357-359` backlog) — only the deduped `CoachCardEntity` survives. The change
is to persist every finding as a `CoachObservation` *before* curating, so curation (and the
profile) become projections of a durable log.

One small helper, called at each analysis site:

```swift
// CoachService
private func recordObservations(
    _ insights: [CoachInsight], for entry: TranscriptEntry, origin: CoachObservation.Origin
) {
    for insight in insights {
        let obs = CoachObservation()
        obs.noteID    = entry.id
        obs.date      = entry.date            // capture date → trends bucket by speaking day
        obs.lensRaw   = insight.lens.rawValue
        obs.originRaw = origin.rawValue
        obs.patternKey = insight.key
        obs.severity  = insight.severity
        obs.span      = insight.originalSpan  // log sites must use `, privacy: .private`
        modelContext.insert(obs)
    }
}
```

LLM lane — single note (`analyzeTranscript`, at ~268) and backlog (`analyzeBacklog`, inside
the per-entry loop at ~337, so we have `entry.id`/`entry.date`, not the merged list):

```swift
let analysis = try await pipeline.analyze(input, profile: &profile, at: now)
recordObservations(analysis.insights, for: entry, origin: .llm)   // ← NEW: persist evidence
// … existing curation stays, now a projection of what we just logged:
let cards = CoachCardCurator.curate(analysis: merged, wins: wins, profile: profile, now: now, limit: perRunCardLimit)
```

Objective lane — per-word GOP (`analyzePronunciation`, ~389), the source of per-word
pronunciation trends. After the result is computed and assigned through the accessor:

```swift
entry.pronunciationResult = result   // → sidecar + on-row summary (via accessor)
for w in result.words {              // ← NEW: one observation per word (fields per PronunciationResult)
    let obs = CoachObservation()
    obs.noteID = entry.id; obs.date = entry.date
    obs.lensRaw = Lens.pronunciation.rawValue
    obs.originRaw = CoachObservation.Origin.objective.rawValue
    obs.word = w.word; obs.gop = w.gop
    modelContext.insert(obs)
}
```

`CoachObservation.Origin` is a small `String`-backed enum (`objective | llm`). Register
`CoachObservation.self` in every `ModelContainer(for:)` (`TranscriptStore.makeContainer`,
and the in-memory containers in `ContentView`, `OnboardingView`, `VocoTests`).

## Opt-in gating

- All coaching tiers (`analysis`, `pronunciationSummaryJSON`, observations, snapshots) are
  absent for notes captured while coaching is off — and the app must render fine that way.
- Coaching history therefore starts at the moment the user enables it. That's expected.
- *Optional product flow (not a migration):* when a user enables coaching, offer to
  analyze their existing un-analyzed notes — the audio/text is still local, so the
  objective lane can run over them on demand. This is a feature, not backfill, and is out
  of scope here.

## Deletion

- `.cascade` on `analysis` removes the sidecar automatically with the entry.
- Still manual: the audio file (`AudioStore` via `audioFilename`), `CoachCardEntity` rows
  where `transcriptID == entry.id`, `CoachObservation` rows where `noteID == entry.id`, and
  the `CoachSnapshot` for the note. (These ride with the History delete feature.)

## Testing (`VocoTests`, in-memory container)

- Accessor round-trips: setting `pronunciationResult` creates the sidecar, reads back
  equal, and populates the on-row `pronunciationSignals`; `wordTimings` round-trips.
- List leanness: fetching entries and reading `text`/`date`/`pronunciationSignals` does not
  require a populated `analysis`.
- Observation log: an analysis run appends one row per finding with correct
  `noteID`/`date`/`lens`/`origin`; a per-word pronunciation query returns dated `gop`s.
- Cascade delete: deleting an entry removes its sidecar; the delete path also clears
  observations/cards/snapshot/audio for that `id`.

## Risks

- **Relationship faulting** — confirm in Instruments that the History query and the digest
  corpus scan don't fault `analysis`. If SwiftData over-fetches, split the heavy blob into
  an unrelated store keyed by `id`.
- **Observation volume** — small append-only rows, but unbounded over years. Keep them
  lean (no spans for objective findings if not needed) and reconsider rollups if the table
  grows large.
- **Coverage is uneven** — objective observations are dense (every analyzed note); LLM
  observations exist only when the (paid/opt-in) LLM lane runs. Consumers must read
  `origin`/`lens` to know what's complete.
```
