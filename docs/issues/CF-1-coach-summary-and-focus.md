# [CF-1] Coach summary & focus — the "what to work on now" surface

- **Phase:** 3 — Notebook & Coach v2 (Coach surface)
- **Depends on:** DM-2 (CoachObservation log), existing `LearnerProfile` (per-lens levels + `RecurringPattern`)
- **Blocks:** CF-3
- **Size:** L
- **Design:** this session (multi-lens focus design)

## Problem
The Coach "Feedback" surface is a flat inbox of per-note `.new` `CoachCardEntity` rows. Across the
**five lenses** (pronunciation, fluency/prosody, vocabulary, grammar, clarity/discourse) and dozens
of notes/day, that's hundreds of items — and most are the same few problems repeated. It is, in the
user's words, "really not usable." A professional coach never hands you a list of 30; they give a
short summary and **one thing to start on**.

## Target user (drives the whole calibration — applies to CF-1/CF-2/CF-3)
The user is **already comfortable speaking English** ("you already speak English for hours a day").
This is a **polish tool for competent speakers, not a learn-English tool.** It changes *what* we
surface and *how* we speak, not the structure:
- **Naturalness over correctness.** Their gaps aren't errors — they're "correct but non-native /
  circuitous / imprecise." The value is *"here's how a native would say what you just said,"* not
  "you made a mistake."
- **Re-weight the lenses.** HIGH value: lexis (word choice / idiom / precision), discourse (clarity /
  concision / directness), prosody (fillers / pace / executive presence). LOW / subtle-only: basic
  grammar (flag only genuine nuance) and pronunciation (only persistent accent features that affect
  how they're *perceived* — never "how to say /θ/"). The ranking must weight accordingly.
- **Respect their competence — raise the precision bar further.** Flagging trivia to a fluent
  speaker is insulting and kills trust. The voice is an **expert peer** ("your next 5%"), never a
  teacher correcting a student. No condescension, no over-explaining basics, no kindergarten
  gamification (think speaking-coach / Grammarly-for-pros, not Duolingo).
- **Frame progress as refinement, not remediation** ("you're below a native filler baseline," "20%
  more direct"), not "errors fixed."

## Principles (this is a professional coaching tool — must be right, reliable, immediately useful)
1. **Summary, not a list.** The default surface is a plain-language coach's recap + a single
   prioritized focus. Enumerable lists are opt-in *depth*, never the front door.
2. **Immediate value.** Answer "what should I work on now, and why" within seconds, with concrete
   evidence from the user's own speech.
3. **Precision over recall.** Only surface a focus area backed by enough evidence (frequency /
   confidence threshold). Being sure about 1–2 beats being noisy about 30 — credibility *is* the
   product. A coaching tool that flags wrong things is worse than one that says less.
4. **Breadth visible, focus singular.** Show all five skill levels (the map) so nothing feels
   hidden; recommend exactly one action.
5. **Positive-leaning.** Lead with a win / measurable progress; corrections are framed as the next
   step, not a verdict.

## Surface (top → bottom)
1. **Weekly summary** — 2–4 sentences that synthesize the coaching across ALL five lenses —
   including the **LLM-derived grammar / word-choice / sentence-structure / clarity** insights, which
   are the substance (the objective metrics are supporting evidence):
   *"This week you spoke ~2h. Your sentences tend to run long — tightening them is your biggest win.
   You also drop articles before abstract nouns (12×). Clarity is improving."*
   v1 is a **grounded LLM recap**, not free-form: the model is handed the already-aggregated,
   already-critic-verified findings (insights + frequencies + objective metrics) and asked to
   **prioritize and phrase** — to *summarize*, never to *generate* new claims. Hallucination risk
   lives in inventing findings; grounding removes it. Two hard rules: (a) **numbers come from our
   aggregation, interpolated into the prose** — the LLM never does arithmetic; (b) **keyless /
   paid-off fallback** = a leaner structured template from the objective signals, so the summary
   degrades rather than disappears. Generate **once per rollup** (per analysis batch / daily-weekly)
   and cache — not per view — to fit cost/cadence control (CE-5).
2. **Skill map** — the five lenses, each a level (`LearnerProfile.levels[Lens]`) + trend arrow.
   Glanceable landscape; tappable → lens detail.
3. **Today's focus** — ONE (occasionally up to 3) prioritized focus area: title, **evidence**
   ("12× this week" + an example span), trend, and a one-tap **Practice** that routes to the
   *matched* drill (CF-2). Chosen by `priority = frequency × severity × trend × learnability ×
   lensWeight`, above an evidence threshold — where `lensWeight` is tuned for the comfortable speaker
   (lexis / discourse / prosody high; basic grammar & pronunciation low). The evidence bar is
   deliberately high so a fluent user is never shown trivia.
4. **Depth on demand** — tap a lens → its specific patterns; **"browse all findings"** demoted to
   here. The old flat list lives in depth — nothing is lost, it just stops being the default.

## Reliability
- Aggregate over `CoachObservation` by `patternKey` / lens with frequency + recency; require **≥N
  occurrences** before a pattern becomes a surfaced focus (configurable; default small but ≥2).
- Objective findings (GOP / fluency) are deterministic. LLM findings are already critic-verified in
  the pipeline — do **not** surface unverified raw insights as focus areas.
- The summary is a **grounded** LLM recap, not free-form: it may reference only the verified
  findings it is given, and all numbers/deltas are computed by us and interpolated (the LLM never
  does math). Keyless → structured-template fallback. This keeps it reliable without giving up the
  qualitative grammar/structure synthesis a pure template can't produce.

## Tasks
- [ ] Replace the flat `.new` card feed in the Coach "Focus" surface with **summary + skill-map +
      single-focus** layout (the curated `CoachCardEntity` list moves to "browse all" in depth).
- [ ] Pure, **unit-tested ranking** over `CoachObservation` + `LearnerProfile.RecurringPattern`:
      frequency, severity, recency-trend, learnability, evidence threshold, lead-with-win. (This is
      exactly the logic that needs a seeded-data runtime check before trust — see the prevention
      work.)
- [ ] Skill map from `LearnerProfile.levels` with trend (from `CoachSnapshot` / observations).
- [ ] Summary generator: a **grounded LLM recap** over the aggregated verified findings (all five
      lenses, grammar/structure included) with our numbers interpolated, cached per rollup; plus a
      **structured-template fallback** from objective signals for the keyless / paid-off path. (Both
      share the same aggregation input so they can't contradict the data.)
- [ ] Lens drill-down + "browse all" demotion.
- [ ] "Practice" CTA → the focus area's matched drill (CF-2).

## Acceptance criteria
- [ ] The default Coach surface shows a summary + five skill levels + one (≤3) prioritized focus —
      **never** a raw list of 20–30.
- [ ] A focus area is surfaced only with sufficient evidence; the ranking is deterministic and unit-tested.
- [ ] Every finding remains reachable via lens drill-down / browse-all.

## Open questions (for review)
- Summary cadence: weekly default + a "today" practice strip (recommended) vs daily.
- ~~v1 summary: template vs LLM~~ → **DECIDED (with you): grounded LLM recap** — summarize verified
  findings incl. grammar/structure; numbers interpolated by us; keyless template fallback; cached per rollup.
- Surface exactly 1 focus vs up to 3 (recommend 1 hero + up to 2 secondary, collapsed).
