# Review/Coach Companion — Design (Phase 2)

**Status:** Draft (from design grilling, 2026-06-26)
**Owner:** Conglei
**Builds on:** [unified-history-data-model.md](unified-history-data-model.md), [coach-v2-design.md](coach-v2-design.md), [notebook-v1-design.md](notebook-v1-design.md)
**Revises (deltas only):** the IA in [ios-ui-design-v1.md](ios-ui-design-v1.md) (§4 below). The locked
screens doc is intentionally left untouched; the IA change is scoped as [RC-7](issues/RC-7-ia-reshuffle.md).

> This is the **differentiator layer**. Phase 1 (keyboard, capture, `TranscriptStore`, History,
> Notes, sync) is built on `main`. Phase 2 turns the accumulated speech into English coaching.

---

## 1. Product thesis

Hex iOS is **a spoken-English improvement companion that learns from the English you already
speak all day.** You dictate across every app (the utility + acquisition hook); the app mines
that real speech and shows you, in a digestible, actionable feed, how to say things better —
then tracks measurable improvement over time and rewards consistency.

**The differentiator** (vs. Superwhisper / Wispr Flow / other dictation apps): they stop at
*good transcription*. Hex uses the transcription as **raw material for improvement**. The
moat is **real examples, not synthetic drills** — you already produce hours of authentic
English daily; that *is* the curriculum, so learning costs zero extra time.

Two hard rules for every learning surface:
1. **Digestible** — one idea per card, quick to consume.
2. **Actionable** — showing a tip you only read is forgettable; every card drives a *do*.

## 2. Target user

**Confident ESL speakers who want to get better** — professionals (engineers, PMs, researchers)
who already speak English all day and want polish, not beginners. Implications:
- Feedback is about **polish** (naturalness, word choice, fluency, conciseness, tone,
  pronunciation), not basic correctness.
- Tone must be **growth-framed**; a nagging grammar-checker or a score that drops will churn
  this user.
- **Beachhead = engineers** → **BYOK is acceptable** for v1 (hypothesis: this cohort won't
  blink at bringing an API key).

## 3. Core loop

```
speak all day (keyboard, across apps)         → corpus accumulates locally (text + audio), day one
  → Coach surfaces a few real "learnable moments" (BYOK analysis, opt-in)
    → you SHADOW a couple (hear it → say it better) or SAVE them
      → streak + measurable per-lens improvement
        → weekly digest shows progress + the next focus
```

Show → **do** → track. The "do" is the point.

## 4. Information architecture (delta vs. locked design)

**Primary tabs:**

| Tab | Role |
|-----|------|
| **Review** (home) | The hero: curated feed of learnable moments + a progress/streak header. The new front door. |
| **Notes** | Secondary, separate: a quick-capture **inbox** for spoken thoughts (capture-and-release; see §11). |
| **Settings** | BYOK/Coach opt-in, capture exclusions, model, sync. |

**Changes from the locked [ios-ui-design-v1.md](ios-ui-design-v1.md) (scoped as [RC-7](issues/RC-7-ia-reshuffle.md)):**
- **Home is no longer a capture screen.** The front door becomes **Review**. Cross-app capture
  happens in the *keyboard*; in-app note capture moves into the *Notes* tab.
- **History is demoted from a primary tab to a "search / browse all my speech" screen** reached
  from Review. (Owner: browsing the raw annotated log isn't the value; per-item annotation lives
  in *item detail*, not a browse surface — §12.)
- Tabs go **Home/History/Settings → Review/Notes/Settings**.

## 5. The Review feed (hero)

A curated, **limited** stream of teachable moments pulled from your real dictations — *not* one
card per mistake. Recurring issues dedupe into a single pattern card.

**Card anatomy:**
> **Context:** "Slack · 9:14am" (real app + time)
> **You said:** the actual snippet from your dictation
> **More natural:** a native-sounding rewrite — or, for a win: "Nicely put 👍"
> **Why:** one line ("'pacific' → 'specific'"; "natives drop the article here")
> **Lens:** one of the five — word choice / grammar / fluency / conciseness / tone / pronunciation
> **Actions:** Say it better (primary) · Save · Got it / Not useful · play audio · see in context

**Mix wins with improvements (positive-leaning).** Surfacing "you phrased this really naturally"
is what keeps a competent speaker motivated and feeds the reward loop. A pure correction stream
demotivates the exact target user.

**Cards derive from existing coach output.** "More natural" = `Feedback.nativeRewrite` (the macOS
popover already renders the same "You → Native" pair); "why"/lens come from `Issue`/`wins`. The feed
is a **curation/presentation layer over `CoachFeedbackEntry`s**, not a new analyzer — see §10.

## 6. Actionability — shadowing + save

- **Primary action: "Say it better" (shadowing).** rephrase → **TTS speaks the natural version**
  (`AVSpeechSynthesizer` on-device for v1; upgrade to neural voices later) → **you repeat it**;
  on-device ASR confirms you produced it (optional cloud delivery check when Coach is on). This
  *is* the drill — but it's **your own real sentence**, which solves "I can't make time for random
  drills." ~10 seconds, active recall, where learning sticks.
- **Secondary: "Save"** → a lightweight personal **phrasebook** ("my natural phrasings") for
  later flick-through review. No folders/organization.
- **Tuning: Got it / Not useful** → trains curation, counts toward the streak.
- Reading the rewrite must be valuable on its own; practice is the high-value *optional* step,
  never a forced gate.

## 7. Progress & reward

Designed so rewards are **always-positive or growth-framed** — **no single score that can drop.**
(The macOS coach's per-session `overallScore` /10 still exists in the model — keep it in **item
detail**, but it is *not* the iOS headline. The headline is the items below.)

- **Streak** — days you reviewed/shadowed ≥1 card. Habit fuel; never punishing.
- **Per-lens deltas** — trend arrows vs. your past self ("fillers 5.1→3.2 /min", "word-choice ↑").
  Improvement is the headline; absolute state is secondary. (Longitudinal layer = coach-v2
  `CoachDigest`.)
- **Milestone wins** — collectible: "Mastered article usage", "100 phrases shadowed", "filler
  rate −30% this month". The dopamine + the proof it works.
- **An only-up level** (optional anchor) — XP from practice/streak; never decreases.
- **Surfacing:** a lightweight header on the Review feed (streak + one trend) that expands into a
  **weekly digest** ("this week: shadowed 14 phrases, fillers ↓, mastered 1 pattern, focus next:
  prepositions").

## 8. Activation model (solving the cold start)

The hero needs analysis, which is **BYOK + opt-in + default-off** — so a new user would open to an
empty hero. Fix: **capture from day one, coach on activation.**

- From first use, the keyboard accumulates dictations **locally** (text + audio) — no analysis, no
  upload. (This is the confirmed default; iOS must **retain audio**, not delete it.)
- Review's empty state is **baited**: *"You've captured 47 things you said this week. Connect a key
  to see how to say them better."*
- The moment a BYOK key is added, Coach analyzes the **backlog** → instant "here are 6 real moments
  from your week" payoff, instead of waiting days. The longer they use the keyboard, the more
  compelling the unlock.
- Onboarding must be **transparent that capture is happening**, with exclusions one tap away (§9).

## 9. Privacy

- **Capture:** everything dictated is stored **locally by default** (text + audio); this is the
  corpus. The corpus never leaves the device on its own.
- **Analysis:** **default-off, opt-in, BYOK** (reuses the existing Coach posture — cloud LLM,
  Keychain key, cloud-upload disclosure naming the provider). Audio/text leave the device only
  when Coach is on and a moment qualifies.
- **Exclusions (must-have):** per-app exclude list (banking, 1Password, specific chats), a quick
  **incognito dictation** toggle, and auto-skip of secure fields. Default = capture-all; exclusion
  = one tap.
- **On-device analysis is the later "mainstream" move** (Apple Foundation Models / local model) to
  make always-on coaching defensible without BYOK; out of scope for this phase.

## 10. The engine is replaced (deep), not reused

> **Correction (2026-06-26):** the existing macOS engine is a stateless one-shot tip generator and is
> **too superficial to be the product's engine.** It is **replaced** by a corpus-stateful coaching
> pipeline — see **[coach-engine-deep-design.md](coach-engine-deep-design.md)** (the core IP). Only
> *plumbing* is reused. The CE-1..CE-5 task series builds the deep engine; the surfaces below (RC-2
> cards, RC-3 feed, RC-6 progress) consume it.

The reuse map / deltas below describe what *plumbing* survives the replacement. Verified state of the
existing engine:

**Reuse as-is (move to HexCore, no rewrite):**
- **Models** — `Feedback {overallScore, summary, nativeRewrite, issues[Issue], wins[], rawMarkdown,
  isStructured}`, `Issue {wordOrPhrase, whatYouSaid, whatToSay, tip}`, `CoachFeedbackEntry`
  (FK `transcriptID`, `provider`, `model`, `costUSDEstimate`), `CoachFeedbackHistory` (max 500).
  All Codable with tolerant decode.
- **Engine** — `CoachClient.analyze` + **`analyzeStream`** (token-streaming), `PronunciationProvider`
  protocol, **Gemini provider live**, **OpenAI is a stub** (`notImplemented`). `PronunciationInput
  {audioURL, durationSec, customPromptTemplate}`, `PronunciationOutput {feedback, model, cost}`.
- **Already shared** — `CoachSettings` is already in HexCore; `KeychainClient` is cross-platform.

**The plumbing port (CE-1):** move the reusable transport/persistence into HexCore; keep a thin TCA
`CoachClient` wrapper per app target so HexCore needn't depend on ComposableArchitecture. iOS adds
BYOK Keychain UI + the cloud-upload disclosure. This is **coach-v2 §7 Option B** (coach on iOS, where
the speech is). The *engine logic* on top is the CE-2..CE-5 deep pipeline, **not** the old one-shot call.

**Deltas — where iOS deliberately diverges from the macOS coach:**

| macOS coach (today) | iOS Review/Coach (this design) |
|---|---|
| **Auto-analyzes every recording ≥ `thresholdSec`** | **Does NOT** — all-day cross-app dictation makes per-utterance cloud analysis cost- and noise-prohibitive. iOS analyzes **curated/batched/on-cadence** + backlog-on-activation, and surfaces running cost (`costUSDEstimate`). |
| Leads with **`overallScore` /10** (red/orange/green, can drop) | Per-session score lives in **item detail only**; the gamified headline is **streak/deltas/wins/level** (never a droppable score) — §7. |
| **Streaming popover** (`CoachPopoverView`), latest + recent list, macOS notifications (`coachNotifier`), `autoShowPopover` | **Review feed** (curated cards) + item detail; streaming reused in detail/on-demand. Notifications optional later. |
| Schema is **pronunciation-shaped** (`Issue` = mispronunciation) | Grows to coach-v2's **5 perspectives** additively (C1); V1 ships on existing `Feedback`/`nativeRewrite`. |

Net: the card's "you said → more natural" **is** the existing `nativeRewrite`; iOS reuses the
engine and re-presents its output. The genuinely net-new iOS work is **curation/cost-control**
(RC-2), the **feed UI** (RC-3), **shadowing/TTS** (RC-4), **phrasebook** (RC-5), and the
**reward layer** (RC-6).

## 11. Notes (secondary) — capture-and-release inbox

Explicit owner direction: **Notes is not a place to organize notes.** It's a quick-capture inbox
for spoken thoughts that you **extract elsewhere** later (paste into your real tool).

- Frictionless in (one tap → speak → saved, raw capture, no titling).
- Easy out (copy / share sheet); optionally an **archive/done** state once moved out.
- **No** folders, tags, smart folders, editing-heavy workflows. Lightweight, "better than Voice
  Memos at capture-a-thought," nothing more (see [notebook-v1-design.md](notebook-v1-design.md)).
- Notes are still `Transcript(kind: .note)` and are **first-class coaching corpus** (long, natural,
  unguarded speech) — see coach-v2 §8.

## 12. Item detail

Tapping a card or a History search result opens **item detail** — this is the *only* place
per-item annotation (option A from grilling) lives:
- full transcript + play audio,
- the coach annotation (natural rewrite + why + lens) if analyzed,
- Say-it-better / Save actions,
- source/context (app, time, duration).

## 13. Dependencies & substrate prerequisites

Verify on `main` before/with [RC-0](issues/RC-0-substrate-prereqs.md):
- **Audio is retained** on iOS (the prototype `DictationModel` historically deleted it).
- **Cross-app/keyboard dictations are persisted** as `Transcript(kind: .dictation, sourceAppName:)`
  — the corpus must include them, not just in-app notes.
- **`Transcript.kind`** enum exists (unified-history-data-model §2.2).
- Coach engine is portable into HexCore (RC-1).

## 14. Phasing

- **Phase 1 — substrate (DONE on `main`):** keyboard, capture, `TranscriptStore`, History, Notes,
  sync. Ships as a private dictation + voice-notes app and accumulates the corpus.
- **Phase 2 — this doc + [coach-engine-deep-design.md](coach-engine-deep-design.md):** Suggested
  order: RC-0 → **CE-1 → CE-2 → CE-3** (the deep engine; CE-4/CE-5 alongside) → RC-2 → RC-3 (feed +
  activation shell) → RC-4/RC-5 (shadow/save) → RC-6 (progress) → RC-7 (IA reshuffle) ‖ RC-8 alongside.
  The deep engine (CE-*) is the critical path — the surfaces are thin without it.

## 15. Task set

| ID | Title | Depends on | Size |
|----|-------|-----------|------|
| [RC-0](issues/RC-0-substrate-prereqs.md) | Substrate prereqs: audio retention + dictations persisted as `Transcript` | — | S |
| **CE-1..CE-5** | **Deep Coach Engine** (replaces RC-1) — see [coach-engine-deep-design.md](coach-engine-deep-design.md) §9 | RC-0 | XL |
| [RC-2](issues/RC-2-card-generation-curation.md) | Learnable-moment card generation + curation | CE-3, CE-2, RC-0 | M |
| [RC-3](issues/RC-3-review-tab-feed.md) | Review tab: feed + activation shell | RC-2 | L |
| [RC-4](issues/RC-4-shadowing-practice.md) | Shadowing practice (rephrase → TTS → repeat) | RC-3 | M |
| [RC-5](issues/RC-5-phrasebook.md) | Save / phrasebook | RC-3 | S |
| [RC-6](issues/RC-6-progress-rewards.md) | Progress & rewards (streak, deltas, wins, level, digest) | CE-2, CE-3 | L |
| [RC-7](issues/RC-7-ia-reshuffle.md) | IA reshuffle: Review home, History→search, capture off home | RC-3 | M |
| [RC-8](issues/RC-8-privacy-capture-controls.md) | Privacy & capture controls (per-app exclude, incognito, secure-field skip) | RC-0 | M |

## 16. Open questions

1. Curation volume — how many cards/day is "a few" (target a default, make it tunable)?
2. "Say it better" delivery scoring — on-device "did you say the words" only in v1, or gate richer
   pronunciation scoring behind BYOK?
3. Longitudinal digest cadence/trigger — weekly auto, on-open, or manual?
4. Default perspective set on first activation (all five vs. a focused default to limit noise/cost).
5. Phrasebook spaced-repetition — v2.1 or just a flat saved list for now?
6. **Analysis trigger & cost at all-day volume.** macOS auto-analyzes every recording ≥ threshold;
   that doesn't scale to all-day cross-app dictation (cost + noise). What's the iOS trigger — daily
   batch? curate-then-analyze a sample? on-demand? — and how do we surface the running `costUSDEstimate`
   so a BYOK user isn't surprised?

## 17. Decisions log (from grilling, 2026-06-26)

| Decision | Why |
|---|---|
| Identity = English-improvement companion from real daily speech; Notes secondary | Owner: dig into voice history to improve the person; differentiator vs. Superwhisper/Wispr |
| Target = confident ESL; engineers as beachhead → BYOK acceptable | Owner hypothesis about early adopters |
| Hero = curated Review feed (B); digest (C) for progress; per-item annotation (A) only in detail | Owner: B + C important; A "too much" as a browse surface |
| Every card must be digestible **and** actionable | Owner: "if we only show it, it won't be useful" |
| Primary action = shadowing (rephrase → TTS → repeat your own real sentence) | Active recall on real examples; solves "no time for random drills" |
| Reward = streak + per-lens deltas + milestone wins + only-up level; **no droppable score** | Competent users churn on grading-down |
| Analysis default-off + BYOK; capture local (text+audio) from day one; analyze backlog on activation | Privacy + cold-start; engineer ICP fine with BYOK |
| IA → Review (home) / Notes / Settings; History demoted to search; capture off home | Owner confirmed; Review is the front door |
| Notes = capture-and-release inbox, not an organizer | Owner: people pull quick thoughts, extract elsewhere later |
| Coach runs on iOS (port to HexCore, Option B) | Coach where the speech is; avoid forcing audio-sync |
