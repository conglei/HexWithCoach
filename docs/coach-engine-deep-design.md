# Coach Engine — Deep Design (corpus-stateful pipeline)

**Status:** Draft (from design grilling, 2026-06-26)
**Owner:** Conglei
**Supersedes:** the "reuse the existing engine" framing in [review-coach-companion-design.md](review-coach-companion-design.md) §10
**Builds on / extends:** [coach-v2-design.md](coach-v2-design.md) (5 perspectives, longitudinal, drills)

> The existing macOS coach is a **stateless, one-shot tip generator** and is too superficial to be
> the product's engine. This doc redesigns it as a **corpus-stateful coaching pipeline**. Only the
> *plumbing* is reused; the shallow one-shot prompt is thrown away.

---

## 0. Why the current engine is superficial (grounded in code)

`Hex/Clients/Providers/GeminiProvider.swift` + `CoachFeature.swift`, verified 2026-06-26:

- **One stateless call** to a **budget model** (`gemini-3.1-flash-lite`, temp 0.2) per recording.
- **Withholds the transcript** on purpose ("rely entirely on what you hear") — even though we already
  have on-device ASR. The model guesses *what* you said *and* judges it, blind.
- **Pronunciation-only**, capped at **3 issues**, **no memory**, **one pass, no verification**.
- **No learner model** — no level, no L1, no recurring patterns, no goals. It can't say "you do this
  every day," which is the entire definition of coaching.

A coach is defined by what this lacks: **it remembers you, it's correct, it hears you, and it gives
you a path.** Those are the four pillars below.

## 1. The four pillars (all required — owner direction)

| Pillar | What it means | Delivered by |
|---|---|---|
| **A. Learner model (memory)** | Knows your level, L1, recurring patterns, habits; personalizes everything | §2 Learner Profile |
| **B. Verified multi-lens rigor** | Correct, specific, rule-grounded feedback across 5 lenses (no shallow/wrong tips) | §3 Tier-1 extract + Tier-2 critic |
| **C. Pronunciation/prosody depth** | Actually *hears* you — real signals, not LLM vibes | §4 |
| **D. Pedagogy** | A real path: notice → practice → reinforce, from your own examples | §5 |

## 2. The Learner Profile (pillar A — the moat)

A persistent, per-user, **evolving** structure derived from the whole corpus. Every analysis is
*conditioned on it and updates it.* Uniquely enabled by all-day capture; impossible for a one-shot
competitor to replicate without your data.

```swift
struct LearnerProfile: Codable, Sendable {
    var inferredL1: String?
    var interferencePatterns: [String]            // L1-typical tendencies
    var levels: [Lens: Int]                        // 1–100 per lens (growth-framed)
    var patterns: [RecurringPattern]               // the heart
    var lexicalProfile: LexicalProfile             // overused words, collocation gaps, range
    var registerTendencies: [String]
    var goals: [String]
    var updatedAt: Date
}

struct RecurringPattern: Codable, Identifiable, Sendable {
    var id: UUID
    var lens: Lens                                 // grammar/lexis/discourse/pronunciation/prosody
    var summary: String                            // "drops articles before abstract nouns"
    var rule: String                               // the teachable rule
    var frequency: Int                             // how often it recurs
    var recency: Date
    var status: PatternStatus                       // .active | .improving | .mastered
    var examples: [ExampleRef]                      // transcriptID + text span (YOUR real examples)
}
```

`patterns` are the curriculum (§5). `status` transitions drive spaced reinforcement and "wins."

## 3. The pipeline (pillar B) — two tiers, verified

Replaces the single call with **extract → verify → integrate → prioritize**. Provider-agnostic.

**Tier 1 — extract** (per curated *batch* of recent dictations; see [RC-2 cost](issues/RC-2-card-generation-curation.md) / CE-5):
- Inputs: `Transcript.text` **+ audio + word timings + the current Profile**.
- Per-lens candidate observations across **grammar/usage · lexis & naturalness · discourse/conciseness
  · pronunciation · prosody & fluency**, each with: evidence span, rule hypothesis, native rewrite,
  severity, `needsAudio`.
- Objective signals (§4) are computed locally and fed in.

**Tier 2 — verify (critic)** — the depth that kills superficiality:
- For each candidate: *is it a real error?* *is the rewrite meaning-preserving and genuinely more
  native?* Drop low-confidence. (A competent user instantly catches a wrong correction.)

**Integrate + prioritize:**
- Survivors merge into the Profile (increment `frequency`, update `recency`/`status`, recompute
  `levels`/trends).
- Pick the **1–2 highest-leverage focuses** (frequency × impact × addressability) — a coach focuses.

**Output:** Review cards, the weekly digest, updated Profile (consumed by RC-2/RC-3/RC-6).

## 4. Pronunciation & prosody (pillar C) — real signals, not vibes

Tiered, per the locked decision:

- **Now — objective signals, local + free:** words/min (pace), pause distribution, **filler rate**
  (um/uh/like), restarts/false-starts — all computable from the ASR transcript + **word timings we
  already have**. Real numbers that feed the fluency/prosody lens and the metrics/trends.
- **Now — multimodal for the linguistic lenses:** feed **transcript + audio** to a strong
  audio-capable model (we *stop withholding the transcript*).
- **Deferred — phoneme-level scoring:** *which sounds* you miss needs more than an LLM — forced
  alignment / Apple Speech analytics / a dedicated pronunciation model. Add as a later depth pass
  once the rest proves out. (Owner: not required for V1.)

## 5. Pedagogy (pillar D) — a path, from your own speech

- **Cards** = your real example → natural rewrite → the *rule* → "5th time this week" (Profile link)
  → **shadow it** (RC-4).
- **Focus** = the prioritized 1–2 patterns to work on now.
- **Spaced reinforcement:** un-mastered `RecurringPattern`s resurface on a cadence; `status` →
  `.mastered` is a **win** (RC-6). The loop is *notice → shadow → reinforce*, never synthetic drills.

## 6. Models & cost

- **Provider-agnostic, BYOK.** Today only **Gemini** is implemented (OpenAI is a stub).
- **Tier the models:** a cheaper model for Tier-1 extraction over batches; a **stronger** model for
  the critic, synthesis, and longitudinal digest; an **audio-capable** model for the pronunciation/
  prosody lens. (The current Flash-Lite is too weak for the critic/synthesis.)
- **Cost control = curated/batched analysis** (CE-5), not per-utterance, + surface the running
  `costUSDEstimate`. Objective signals (§4) are free and carry a lot of the fluency value.

## 7. Reuse map — what survives vs. what's thrown away

**Reuse (plumbing → HexCore):** the Gemini HTTP/SSE transport + JSON extraction (generalize into a
provider transport), `KeychainClient` BYOK, `CoachFeedbackEntry`/`CoachFeedbackHistory` persistence,
the `Transcript` corpus, `CoachSettings`.

**Throw away:** the one-shot `defaultPromptTemplate`, the single-pass `CoachMarkdownParser` flow, the
pronunciation-only `Feedback` schema (grows to per-lens + Profile), and the "withhold the transcript"
assumption.

## 8. Schema evolution

- Per-lens structured output (aligns with coach-v2 `PerspectiveFeedback`/`SessionFeedback`).
- New: `LearnerProfile`, `RecurringPattern`, objective `metrics` (`fillersPerMin`, `wordsPerMin`, …).
- Back-compat: old `Feedback` decodes into a single pronunciation-lens result; old history still loads.

## 9. Task set (CE series)

| ID | Title | Depends on | Size |
|----|-------|-----------|------|
| [CE-1](issues/CE-1-engine-foundation.md) | Engine foundation + provider transport in HexCore + iOS BYOK | — | L |
| [CE-2](issues/CE-2-learner-profile.md) | Learner Profile: model, store, update logic | CE-1 | L |
| [CE-3](issues/CE-3-multilens-verify-pipeline.md) | Multi-lens extract + critic verify + prioritize + integrate | CE-1, CE-2 | L |
| [CE-4](issues/CE-4-prosody-fluency-signals.md) | Objective prosody/fluency signals + multimodal pronunciation lens | CE-1 | M |
| [CE-5](issues/CE-5-cadence-cost-control.md) | Analysis cadence + cost control (curated/batched, model tiering, cost surfacing) | CE-1 | M |

These replace the old "[RC-1] port" task. The Phase-2 surfaces consume them: RC-2 (cards) ← CE-3/CE-2;
RC-6 (progress) ← CE-2/CE-3.

## 10. Open questions

1. **Profile update mechanics** — LLM-maintained structured Profile vs. computed metrics + LLM
   narrative? How do we keep it stable/auditable across runs (don't let it drift)?
2. **Critic strength vs. cost** — separate critic pass, or a self-check within one stronger call?
3. **Batch size & cadence** (CE-5) — daily? on-open? N-dictations? balances cost vs. freshness.
4. **Default model tiers** per stage for the BYOK provider(s).
5. **L1 inference** — infer from speech, or ask the user once (cheaper, more reliable)?

## 11. Decisions log (grilling, 2026-06-26)

| Decision | Why |
|---|---|
| Replace the engine; reuse only plumbing | Current engine is a stateless one-shot tip generator — too superficial |
| All four pillars required (learner model, verified multi-lens, pronunciation/prosody, pedagogy) | Owner: all important |
| Corpus-stateful **Learner Profile** is the spine/moat | Turns tips into coaching; uniquely enabled by all-day corpus |
| Two-tier **extract → verify** pipeline | Verification kills the superficial/wrong feedback competent users reject |
| Feed the ASR transcript (stop withholding it) | Today's engine guesses what you said *and* judges it — the dumbest weakness |
| Pronunciation: objective signals + multimodal now; phoneme forced-alignment later | Real (not vibes) fluency now; deep phonetics is a later specialized pass |
| Tier the models; cost via curated/batched analysis | Deep multi-pass over an all-day corpus must be cost-controlled |
