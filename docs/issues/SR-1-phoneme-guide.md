# [SR-1] Phoneme guide: plain-English anchors + articulation tips

- **Phase:** 3 — Notebook & Coach v2 (Shadowing result)
- **Depends on:** —
- **Blocks:** SR-2
- **Size:** S
- **Design:** this session (Say-it-better redesign)

## Goal
A pure, testable lookup that turns a raw IPA phoneme into something a learner can act on: an
**exemplar word** ("/ɑ/ as in *rob*") and a one-line **articulation tip** ("drop your jaw, keep
it short"). Bare IPA tells an advanced learner what's wrong; the anchor + tip tells *everyone* how
to fix it. SR-2 renders feedback through this.

## Tasks
- [ ] Add a `PhonemeGuide` (pure value type / enum) in `VocoCore` mapping each IPA symbol the GOP
      model can emit → `{ exemplar: String (a common word containing the sound, with the sound
      itself marked or obvious), tip: String (≤ ~12 words, how to make it) }`.
- [ ] Cover the full phoneme inventory used by `PronunciationResult`/`PronunciationSignals`
      (inspect the GOP model's symbol set in `VocoCore` — match exactly so nothing is unmapped).
- [ ] `func guide(for phoneme: String) -> PhonemeGuide.Entry?` (nil-safe; unknown symbol → nil so
      callers fall back to bare IPA, never crash).
- [ ] Optional helper to phrase a substitution: `"you said /oʊ/ (as in \"robe\") — aim for /ɑ/ (as in \"rob\")"`.

## Tests (`VocoCore/Tests/VocoCoreTests`, `swift test`)
- [ ] Every phoneme symbol the GOP model emits has a non-empty exemplar + tip (drive the assertion
      off the model's symbol inventory so coverage can't silently rot).
- [ ] Unknown symbol → nil; the substitution-phrasing helper formats as expected.

## Acceptance criteria
- [ ] No phoneme the pipeline can produce is left without an anchor/tip.
- [ ] Pure, no UIKit/SwiftUI imports; `swift test` green.
