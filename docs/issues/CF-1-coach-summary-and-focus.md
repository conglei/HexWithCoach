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
1. **Weekly summary** — 2–4 sentences, plain language, generated from aggregated signals:
   *"This week you spoke ~2h. Clarity is improving. The one thing holding you back: you drop
   articles — 12 times. A 2-minute drill below."* v1 is **template-bound from deterministic
   signals** (no LLM in the headline) for reliability; LLM phrasing can enhance later, gated/cheap.
2. **Skill map** — the five lenses, each a level (`LearnerProfile.levels[Lens]`) + trend arrow.
   Glanceable landscape; tappable → lens detail.
3. **Today's focus** — ONE (occasionally up to 3) prioritized focus area: title, **evidence**
   ("12× this week" + an example span), trend, and a one-tap **Practice** that routes to the
   *matched* drill (CF-2). Chosen by `priority = frequency × severity × trend × learnability`, above
   an evidence threshold.
4. **Depth on demand** — tap a lens → its specific patterns; **"browse all findings"** demoted to
   here. The old flat list lives in depth — nothing is lost, it just stops being the default.

## Reliability
- Aggregate over `CoachObservation` by `patternKey` / lens with frequency + recency; require **≥N
  occurrences** before a pattern becomes a surfaced focus (configurable; default small but ≥2).
- Objective findings (GOP / fluency) are deterministic. LLM findings are already critic-verified in
  the pipeline — do **not** surface unverified raw insights as focus areas.
- The summary must never contradict the data — template-bound in v1 so the headline can't
  hallucinate.

## Tasks
- [ ] Replace the flat `.new` card feed in the Coach "Focus" surface with **summary + skill-map +
      single-focus** layout (the curated `CoachCardEntity` list moves to "browse all" in depth).
- [ ] Pure, **unit-tested ranking** over `CoachObservation` + `LearnerProfile.RecurringPattern`:
      frequency, severity, recency-trend, learnability, evidence threshold, lead-with-win. (This is
      exactly the logic that needs a seeded-data runtime check before trust — see the prevention
      work.)
- [ ] Skill map from `LearnerProfile.levels` with trend (from `CoachSnapshot` / observations).
- [ ] Summary generator: a pure function from deterministic signals → sentences (pluggable so LLM
      phrasing can swap in later).
- [ ] Lens drill-down + "browse all" demotion.
- [ ] "Practice" CTA → the focus area's matched drill (CF-2).

## Acceptance criteria
- [ ] The default Coach surface shows a summary + five skill levels + one (≤3) prioritized focus —
      **never** a raw list of 20–30.
- [ ] A focus area is surfaced only with sufficient evidence; the ranking is deterministic and unit-tested.
- [ ] Every finding remains reachable via lens drill-down / browse-all.

## Open questions (for review)
- Summary cadence: weekly default + a "today" practice strip (recommended) vs daily.
- v1 summary: template (recommended, reliable/cheap) vs LLM-phrased.
- Surface exactly 1 focus vs up to 3 (recommend 1 hero + up to 2 secondary, collapsed).
