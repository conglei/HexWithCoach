# [CF-2] Typed practice framework — drills matched to the lens

- **Phase:** 3 — Notebook & Coach v2 (Coach surface)
- **Depends on:** PR-1 (PracticeItem), SR-1/SR-2 (shadowing = the pronunciation drill)
- **Blocks:** CF-3
- **Size:** L
- **Design:** this session (typed practice)

## Problem
Practice today is **only shadowing** ("hear → say → GOP"), which fits only pronunciation/prosody.
Vocabulary, grammar, and clarity problems need *different* drills — the learning is in the
choice/production, not the mouth. Practicing a word-choice issue by shadowing the corrected sentence
is ineffective: it rehearses the sounds, not the decision. To be a real coaching tool, practice has
to be a **family of drills, each matched to the lens**, and the system must pick the right one.

## Principles (effective practice)
- **Right drill for the problem.** The focus area's lens determines the drill kind; the user never
  picks a drill type — that's what makes focus effortless.
- **Active production, not passive reading.** The user must *produce* the stronger word / corrected
  form / clearer version, not just see it. Recognition is a warm-up; production is the learning.
- **Their own sentences.** Targets come from the user's real speech (`CoachInsight.originalSpan` /
  `context`), so practice transfers to real use.
- **Short, spaced, scored.** ~30s per rep, resurfaced over days, with a per-kind feedback signal.

## The abstraction
Generalize `PracticeItem` with a `kind`, and define a `PracticeDrill` per kind =
`{ content (from a CoachInsight / focus area), interaction, scoring/feedback signal }`:

| kind | lens | interaction | feedback signal |
|------|------|-------------|-----------------|
| `shadow` | pronunciation / prosody | hear → say → repeat | GOP / ASR match (**exists**, SR-2) |
| `reSayClean` | fluency | re-speak minimizing fillers / pace | filler-rate ↓, WPM |
| `wordSwap` | vocabulary | choose then **produce** a stronger word | judge (heuristic / LLM) |
| `fixForm` | grammar | produce the corrected form (cloze / transform) | rule / LLM check |
| `condense` | clarity / discourse | say it shorter & clearer vs a model | judge + length |

## Scope for THIS issue (prove the abstraction, don't build all five)
- [ ] Add `PracticeItem.kind` + a `PracticeDrill` protocol (`content` / `interaction` / `score`),
      and **refactor the existing shadowing into a `ShadowDrill`** conforming to it — no behavior
      regression (SR-2's result screen is the shadow drill's result view).
- [ ] Implement ONE new non-pronunciation kind end-to-end to validate the abstraction: **`wordSwap`**
      (vocabulary) — highest value, clearest interaction. Content from
      `CoachInsight.originalSpan → nativeRewrite`; require **production**; score with a judge (v1:
      heuristic — did they produce the target or an acceptable synonym; optional LLM judge in the
      paid lane).
- [ ] The focus area's lens selects the kind (wired from CF-1's Practice CTA).
- [ ] Persist attempts tagged with `kind` (feeds CF-3).
- **Follow-up issues (not here):** `fixForm` (grammar), `condense` (clarity), `reSayClean` (fluency)
  — each is a new conformer, not a rewrite, if the abstraction is right.

## Reliability
- Judged drills must **degrade gracefully without the paid lane** (heuristic check or guided
  self-assessment); never block practice on the network.
- Never mark "correct" unless confident; favor encouraging, non-punitive feedback ("closer — the
  native choice here is X") over a hard wrong.

## Acceptance criteria
- [ ] A `PracticeDrill` abstraction exists with `shadow` refactored in + `wordSwap` implemented; a
      new kind is a new conformer, not a rewrite of the practice surface.
- [ ] Practicing a **vocabulary** focus launches a word-swap drill (not shadowing); attempts persist
      with their `kind`.
- [ ] Existing shadowing (all SR-2 callers + the PR-3 paste session) is unchanged.

## Open questions (for review)
- `wordSwap` judging for v1: heuristic-only vs heuristic + optional LLM (recommend heuristic + LLM-when-available).
- How much drill content is derivable from existing `CoachInsight` fields vs needs generation.
- Recognition-then-production vs production-only for `wordSwap` (recommend a quick recognition warm-up → production).
