//
//  DebugSeed.swift
//  Voco
//
//  SEED — a DEBUG-only sample-data harness. The team kept shipping screens that
//  look fine empty but break with real data (the Coach feed was empty in
//  production; the History header glitched). There was no way to get realistic
//  data into the app without running the whole capture → coach flow by hand.
//
//  `DebugSeed.seed(...)` injects a realistic, internally-consistent corpus into
//  the *live* stores — the SwiftData `ModelContainer` (notes, coach cards,
//  observations, practice) and the file-backed Coach stores (learner profile +
//  growth snapshots) — so any screen can be developed/QA'd with data.
//
//  Triggers (both DEBUG-only):
//    • Settings ▸ Developer ▸ "Seed sample data" button.
//    • Launch flag: set the env var `VOCO_SEED=1` (Scheme ▸ Run ▸ Arguments ▸
//      Environment Variables) so an automated screenshot run can seed without
//      tapping. `DebugSeed.seedIfRequestedAtLaunch(...)` reads it at startup.
//
//  Idempotent: seeding clears the previously-seeded corpus first (tagged via a
//  sentinel `sourceAppName` / pattern keys) so repeated runs don't pile up.
//
//  EVERYTHING in this file is gated behind `#if DEBUG`, so none of it ships in a
//  release build.
//

#if DEBUG

import Foundation
import VocoCore
import SwiftData
import os

enum DebugSeed {
    /// Marker stamped on every seeded `TranscriptEntry.sourceAppName` so a re-seed
    /// can find and remove the prior sample corpus without touching real captures.
    static let marker = "voco.debug.seed"

    private static let log = Logger(subsystem: "co.stonefrontier.voco", category: "DebugSeed")

    // MARK: - Launch trigger

    /// Whether the process was launched asking to seed (env `VOCO_SEED=1` or the
    /// `-VOCOSeed` launch argument). Cheap; safe to call anywhere.
    static var isRequestedAtLaunch: Bool {
        let env = ProcessInfo.processInfo.environment
        if let v = env["VOCO_SEED"], ["1", "true", "yes", "YES"].contains(v) { return true }
        if ProcessInfo.processInfo.arguments.contains("-VOCOSeed") { return true }
        return false
    }

    /// Seed the live stores if the launch flag is set. No-op otherwise. Called once
    /// from the app entry point at startup.
    @MainActor
    static func seedIfRequestedAtLaunch(into context: ModelContext) {
        guard isRequestedAtLaunch else { return }
        log.notice("VOCO_SEED launch flag set — seeding sample data.")
        seed(into: context)
    }

    // MARK: - Entry point

    /// Clear any prior seeded corpus, then inject a fresh realistic sample set into
    /// both the SwiftData container and the file-backed Coach stores. Idempotent.
    @MainActor
    static func seed(into context: ModelContext) {
        clear(context)

        let cal = Calendar.current
        let now = Date()
        func daysAgo(_ d: Int, hour: Int = 10, minute: Int = 0) -> Date {
            let base = cal.date(byAdding: .day, value: -d, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        // MARK: Notes / dictations (TranscriptEntry)
        // ~12 entries across today, yesterday, last week. Mixed kinds. The
        // `sourceAppName` carries our marker so a re-seed can find them; for
        // dictations we still want a believable host app, so we suffix the marker.
        struct NoteSpec {
            let text: String
            let date: Date
            let kind: TranscriptKind
            let host: String?
        }
        let noteSpecs: [NoteSpec] = [
            .init(text: "Reminder to send the quarterly report to the design team before our sync tomorrow morning.",
                  date: daysAgo(0, hour: 9, minute: 12), kind: .note, host: nil),
            .init(text: "I think we should focus on the onboarding flow first because that's where most users drop off.",
                  date: daysAgo(0, hour: 14, minute: 40), kind: .dictation, host: "Slack"),
            .init(text: "Grocery list: oat milk, spinach, the good sourdough, coffee beans, and more of those almonds.",
                  date: daysAgo(0, hour: 18, minute: 5), kind: .note, host: nil),
            .init(text: "Following up on yesterday's call — I will draft the proposal and circulate it by end of week.",
                  date: daysAgo(1, hour: 8, minute: 50), kind: .dictation, host: "Mail"),
            .init(text: "Idea for the app: a weekly digest that shows how your speaking has actually improved over time.",
                  date: daysAgo(1, hour: 13, minute: 22), kind: .note, host: nil),
            .init(text: "Note to self, I keep saying basically too much in meetings, I should really watch that habit.",
                  date: daysAgo(1, hour: 21, minute: 10), kind: .note, host: nil),
            .init(text: "Can you confirm whether the client wants the invoice split monthly or as a single payment?",
                  date: daysAgo(3, hour: 11, minute: 30), kind: .dictation, host: "Messages"),
            .init(text: "The conference talk went well overall, although I rushed the middle section a little bit.",
                  date: daysAgo(4, hour: 16, minute: 0), kind: .note, host: nil),
            .init(text: "Let's schedule the retro for Thursday afternoon and make sure everyone adds their notes beforehand.",
                  date: daysAgo(6, hour: 10, minute: 15), kind: .dictation, host: "Notes"),
            .init(text: "I really enjoyed the book about deep work, it changed how I think about my mornings completely.",
                  date: daysAgo(7, hour: 7, minute: 45), kind: .note, host: nil),
            .init(text: "We need to comfortable schedule a thorough review of the architecture before the next release.",
                  date: daysAgo(8, hour: 15, minute: 20), kind: .note, host: nil),
            .init(text: "Thanks again for the introduction, I will reach out to her team early next week to set things up.",
                  date: daysAgo(10, hour: 12, minute: 0), kind: .dictation, host: "Mail"),
        ]

        var entries: [TranscriptEntry] = []
        for spec in noteSpecs {
            let host: String?
            switch spec.kind {
            case .note: host = marker
            case .dictation: host = "\(spec.host ?? "App") · \(marker)"
            }
            let entry = TranscriptEntry(text: spec.text, date: spec.date, kind: spec.kind, sourceAppName: host)
            context.insert(entry)
            entries.append(entry)
        }

        // Convenience: pick a representative note id for card / observation links.
        func note(_ i: Int) -> TranscriptEntry { entries[min(i, entries.count - 1)] }

        // MARK: Coach cards (CoachCardEntity) across ALL FIVE lenses
        // Built from pure CoachCards so practiceText / nativeRewrite / originalSpan
        // are populated and transcriptIDs point at real seeded notes.
        struct CardSpec {
            let lens: Lens
            let kind: CoachCardKind
            let key: String
            let title: String
            let detail: String
            let original: String?
            let rewrite: String?
            let practice: String?
            let context: String?
            let recurrence: String?
            let status: CoachCardStatus
            let noteIndex: Int
            let daysAgo: Int
        }
        let cardSpecs: [CardSpec] = [
            // grammar
            .init(lens: .grammar, kind: .improvement, key: "drop-articles",
                  title: "Add the missing article",
                  detail: "English needs an article before most singular nouns. Try \u{201C}the\u{201D} or \u{201C}a\u{201D} here.",
                  original: "send the quarterly report to design team",
                  rewrite: "send the quarterly report to the design team",
                  practice: "Send the quarterly report to the design team before our sync.",
                  context: "before our sync tomorrow morning", recurrence: "Came up 12\u{00D7} \u{2014} here's the pattern.",
                  status: .new, noteIndex: 0, daysAgo: 0),
            // lexis
            .init(lens: .lexis, kind: .improvement, key: "overuse-basically",
                  title: "A crisper word than \u{201C}basically\u{201D}",
                  detail: "\u{201C}Basically\u{201D} is a filler here \u{2014} cutting it makes the sentence land harder.",
                  original: "I keep saying basically too much",
                  rewrite: "I overuse \u{201C}basically\u{201D} in meetings",
                  practice: "I overuse the word basically in meetings and I want to cut it.",
                  context: "I should really watch that habit", recurrence: "Came up 9\u{00D7} \u{2014} here's the pattern.",
                  status: .new, noteIndex: 5, daysAgo: 1),
            // discourse
            .init(lens: .discourse, kind: .improvement, key: "tighten-clause",
                  title: "Tighten the sentence",
                  detail: "Two ideas are stitched with a comma. A period (or a clearer link) reads more confidently.",
                  original: "it changed how I think about my mornings completely",
                  rewrite: "It completely changed how I think about my mornings.",
                  practice: "It completely changed how I think about my mornings.",
                  context: "the book about deep work", recurrence: nil,
                  status: .saved, noteIndex: 9, daysAgo: 7),
            // pronunciation
            .init(lens: .pronunciation, kind: .improvement, key: "th-thorough",
                  title: "The /\u{03B8}/ in \u{201C}thorough\u{201D}",
                  detail: "Put your tongue between your teeth for the \u{201C}th\u{201D} \u{2014} it tends to slip toward an /s/ or /f/.",
                  original: "a thorough review of the architecture",
                  rewrite: "a thorough review of the architecture",
                  practice: "We need a thorough review of the architecture before release.",
                  context: "before the next release", recurrence: "Came up 8\u{00D7} \u{2014} here's the pattern.",
                  status: .new, noteIndex: 10, daysAgo: 8),
            // prosody / fluency
            .init(lens: .prosody, kind: .improvement, key: "rushed-pacing",
                  title: "Slow the middle section",
                  detail: "Your pace spikes mid-thought. A short pause before the key point gives it room to breathe.",
                  original: "I rushed the middle section a little bit",
                  rewrite: "I rushed the middle section a little",
                  practice: "The talk went well, although I rushed the middle section a little.",
                  context: "the conference talk went well overall", recurrence: nil,
                  status: .saved, noteIndex: 7, daysAgo: 4),
            // a couple more .new cards to fill the feed
            .init(lens: .grammar, kind: .improvement, key: "subject-verb",
                  title: "Match the verb to the subject",
                  detail: "\u{201C}Everyone\u{201D} takes a singular verb. Small slip, easy fix.",
                  original: "make sure everyone add their notes",
                  rewrite: "make sure everyone adds their notes",
                  practice: "Make sure everyone adds their notes beforehand.",
                  context: "schedule the retro for Thursday", recurrence: nil,
                  status: .new, noteIndex: 8, daysAgo: 6),
            .init(lens: .lexis, kind: .improvement, key: "collocation-make-payment",
                  title: "Natural collocation: \u{201C}make a payment\u{201D}",
                  detail: "We \u{201C}make\u{201D} a payment rather than \u{201C}do\u{201D} one \u{2014} a common collocation gap.",
                  original: "as a single payment",
                  rewrite: "make a single payment",
                  practice: "Does the client want to make monthly payments or a single payment?",
                  context: "split monthly or as a single payment", recurrence: nil,
                  status: .new, noteIndex: 6, daysAgo: 3),
            // a win card so the feed leads with a positive
            .init(lens: .prosody, kind: .win, key: "fillers-mastered",
                  title: "Mastered: fewer filler words",
                  detail: "You've stopped leaning on \u{201C}um\u{201D} and \u{201C}uh\u{201D} \u{2014} nice work.",
                  original: nil, rewrite: nil, practice: nil, context: nil, recurrence: nil,
                  status: .new, noteIndex: 1, daysAgo: 0),
        ]

        for spec in cardSpecs {
            let card = CoachCard(
                kind: spec.kind, lens: spec.lens, key: spec.key,
                title: spec.title, detail: spec.detail,
                originalSpan: spec.original, nativeRewrite: spec.rewrite,
                context: spec.context, practiceText: spec.practice,
                transcriptID: note(spec.noteIndex).id, recurrenceNote: spec.recurrence,
                createdAt: daysAgo(spec.daysAgo, hour: 11), origin: .llm
            )
            let entity = CoachCardEntity(card: card)
            entity.status = spec.status
            entity.createdAt = card.createdAt
            context.insert(entity)
        }

        // MARK: Observations (CoachObservation)
        // MANY per a few patternKeys + across dates so frequency/recency/trends have
        // real signal. patternKeys match the seeded RecurringPatterns below.
        // 1) "drop-articles" — 12 LLM-lane rows across grammar.
        seedObservationCluster(
            context: context, lens: .grammar, key: "drop-articles", count: 12,
            spans: [
                "go to store", "send to design team", "review of architecture",
                "before next release", "draft proposal", "schedule retro",
            ],
            noteFor: { entries[$0 % entries.count] }, daysAgoFor: { ($0 * 1) % 12 },
            severity: 3, daysAgoRef: daysAgo)
        // 2) filler "overuse-basically" — lexis rows shaped as a genuine
        //    practice→frequency-drop (CF-3): heavy BEFORE the first practice rep
        //    (day 14), sparse AFTER. ~3/active-day before, ~1/active-day after, so the
        //    honesty guard clears and the "it's working" card fires for the seed.
        let basicallySpans = ["basically just", "basically the same", "I basically think"]
        // Before practice: days 30…16, 3 occurrences per active day (the baseline).
        var bIdx = 0
        for day in stride(from: 30, through: 16, by: -2) {
            for _ in 0..<3 {
                let n = entries[(bIdx + 2) % entries.count]
                let obs = CoachObservation(
                    noteID: n.id, date: daysAgo(day, hour: 14),
                    lensRaw: Lens.lexis.rawValue, originRaw: CoachObservation.Origin.llm.rawValue,
                    patternKey: "overuse-basically", word: nil, gop: nil,
                    severity: 2, span: basicallySpans[bIdx % basicallySpans.count])
                context.insert(obs)
                bIdx += 1
            }
        }
        // After practice: days 10…0, 1 occurrence per active day (the drop).
        for day in stride(from: 10, through: 0, by: -2) {
            let n = entries[(bIdx + 2) % entries.count]
            let obs = CoachObservation(
                noteID: n.id, date: daysAgo(day, hour: 14),
                lensRaw: Lens.lexis.rawValue, originRaw: CoachObservation.Origin.llm.rawValue,
                patternKey: "overuse-basically", word: nil, gop: nil,
                severity: 2, span: basicallySpans[bIdx % basicallySpans.count])
            context.insert(obs)
            bIdx += 1
        }
        // 3) per-word /θ/ pronunciation issue — 8 objective GOP rows for "thorough".
        for i in 0..<8 {
            let n = entries[(i + 3) % entries.count]
            let obs = CoachObservation(
                noteID: n.id, date: daysAgo((i * 1) % 9, hour: 15),
                lensRaw: Lens.pronunciation.rawValue, originRaw: CoachObservation.Origin.objective.rawValue,
                patternKey: nil, word: "thorough", gop: -4.2 + Double(i) * 0.35,
                severity: 0, span: nil)
            context.insert(obs)
        }
        // A few more per-word pronunciation rows for variety / detail screens.
        for (i, word) in ["schedule", "comfortable", "specifically"].enumerated() {
            for j in 0..<3 {
                let n = entries[(i + j) % entries.count]
                let obs = CoachObservation(
                    noteID: n.id, date: daysAgo((j * 2) % 8, hour: 16),
                    lensRaw: Lens.pronunciation.rawValue, originRaw: CoachObservation.Origin.objective.rawValue,
                    patternKey: nil, word: word, gop: -3.0 + Double(j) * 0.5,
                    severity: 0, span: nil)
                context.insert(obs)
            }
        }

        // MARK: Practice (PracticeItem + PracticeAttempt)
        // CF-3: tag the item with its focus area (lens + patternKey) so the recorded
        // attempts are attributable to the `th-thorough` pattern — closing the loop.
        let practice1 = PracticeStore.coachInsight(
            "We need a thorough review of the architecture before the next release.",
            segments: [
                "We need a thorough review of the architecture",
                "before the next release.",
            ],
            sourceID: note(10).id, patternKey: "th-thorough", lens: .pronunciation,
            title: "The /\u{03B8}/ in \u{201C}thorough\u{201D}")
        practice1.createdAt = daysAgo(2, hour: 9)
        context.insert(practice1)
        let attempt1a = PracticeAttempt(
            date: daysAgo(2, hour: 9), perSegmentScores: [0.71, 0.82], gopDelta: nil, item: practice1)
        let attempt1b = PracticeAttempt(
            date: daysAgo(1, hour: 9), perSegmentScores: [0.84, 0.91], gopDelta: 0.6, item: practice1)
        context.insert(attempt1a)
        context.insert(attempt1b)

        // CF-2/CF-3: a word-swap (lexis) practice item, tagged `.wordSwap` AND tagged
        // with the `overuse-basically` focus area, so the kind-aware accumulation
        // strip shows a non-shadow drill and the practice→frequency-drop loop can
        // attribute reps to the lexis pattern below.
        let practice2 = PracticeStore.coachInsight(
            "I overuse basically in meetings",
            segments: ["I overuse basically in meetings"],
            sourceID: note(5).id, kind: .wordSwap,
            patternKey: "overuse-basically", lens: .lexis,
            title: "A crisper word than \u{201C}basically\u{201D}")
        practice2.createdAt = daysAgo(0, hour: 19)
        context.insert(practice2)
        // Several reps over the last two weeks so the accumulation strip reads as a
        // real habit and the frequency-drop signal has enough practice evidence.
        let practice2Attempts: [(Int, Double)] = [(14, 0.61), (12, 0.66), (8, 0.74), (4, 0.81), (0, 0.86)]
        for (d, score) in practice2Attempts {
            let a = PracticeAttempt(
                date: daysAgo(d, hour: 19), perSegmentScores: [score], gopDelta: nil, item: practice2)
            context.insert(a)
        }

        do {
            try context.save()
        } catch {
            log.error("DebugSeed: SwiftData save failed: \(String(describing: error), privacy: .public)")
        }

        // MARK: File-backed Coach stores (LearnerProfile + CoachSnapshots)
        seedLearnerProfile(entries: entries, daysAgoRef: daysAgo)
        seedSnapshots(entries: entries)

        log.notice("DebugSeed: seeded \(entries.count, privacy: .public) notes, \(cardSpecs.count, privacy: .public) cards, plus observations, profile, snapshots and practice.")
    }

    // MARK: - Clear (idempotency)

    /// Remove the previously-seeded SwiftData corpus and reset the file-backed Coach
    /// stores, so a re-seed doesn't accumulate. Only touches seeded data: notes are
    /// matched by the `marker` in `sourceAppName`; cards/observations/practice by the
    /// seeded pattern keys / sources. The file-backed profile + snapshot stores are
    /// fully overwritten on each seed, so they need no separate clear.
    @MainActor
    static func clear(_ context: ModelContext) {
        // Notes tagged with the marker, and their cascade (analysis).
        if let notes = try? context.fetch(FetchDescriptor<TranscriptEntry>()) {
            let seeded = notes.filter { ($0.sourceAppName ?? "").contains(marker) }
            let seededIDs = Set(seeded.map(\.id))
            for n in seeded { context.delete(n) }

            // Cards / observations / practice that point at those notes.
            if let cards = try? context.fetch(FetchDescriptor<CoachCardEntity>()) {
                for c in cards where c.transcriptID.map(seededIDs.contains) ?? false { context.delete(c) }
            }
            if let obs = try? context.fetch(FetchDescriptor<CoachObservation>()) {
                for o in obs where seededIDs.contains(o.noteID) { context.delete(o) }
            }
            if let items = try? context.fetch(FetchDescriptor<PracticeItem>()) {
                for item in items where item.sourceID.map(seededIDs.contains) ?? false { context.delete(item) }
            }
        }
        try? context.save()
    }

    // MARK: - Helpers

    @MainActor
    private static func seedObservationCluster(
        context: ModelContext,
        lens: Lens, key: String, count: Int,
        spans: [String],
        noteFor: (Int) -> TranscriptEntry,
        daysAgoFor: (Int) -> Int,
        severity: Int,
        daysAgoRef: (Int, Int, Int) -> Date
    ) {
        for i in 0..<count {
            let n = noteFor(i)
            let obs = CoachObservation(
                noteID: n.id,
                date: daysAgoRef(daysAgoFor(i), 14, 0),
                lensRaw: lens.rawValue,
                originRaw: CoachObservation.Origin.llm.rawValue,
                patternKey: key,
                word: nil,
                gop: nil,
                severity: severity,
                span: spans[i % spans.count])
            context.insert(obs)
        }
    }

    // MARK: - File-backed stores

    /// The seeded profile/snapshot files MUST land where the live readers look, so
    /// resolve through the single source of truth (`CoachPaths`) — never an inline
    /// copy of the path logic, which is exactly how the drift this guards against
    /// crept in.
    private static var profileStore: LearnerProfileStore {
        LearnerProfileStore(url: CoachPaths.profileURL())
    }

    private static var snapshotStore: CoachSnapshotStore {
        CoachSnapshotStore(url: CoachPaths.snapshotsURL())
    }

    /// Seed a LearnerProfile with per-lens levels and a set of RecurringPatterns
    /// whose keys match the seeded observations. One pattern is old enough to be
    /// `.mastered` (a win), others active/improving, with real firstSeen/recency.
    private static func seedLearnerProfile(
        entries: [TranscriptEntry],
        daysAgoRef: (Int, Int, Int) -> Date
    ) {
        func example(_ i: Int, _ span: String) -> ExampleRef {
            ExampleRef(transcriptID: entries[min(i, entries.count - 1)].id, span: span)
        }

        let patterns: [RecurringPattern] = [
            RecurringPattern(
                lens: .grammar, key: "drop-articles",
                summary: "drops articles before nouns",
                rule: "Use \u{201C}the\u{201D}/\u{201C}a\u{201D} before most singular nouns.",
                frequency: 12, firstSeen: daysAgoRef(40, 10, 0), recency: daysAgoRef(0, 10, 0),
                status: .active,
                examples: [example(0, "send to design team"), example(10, "review of architecture")]),
            RecurringPattern(
                lens: .lexis, key: "overuse-basically",
                summary: "overuses \u{201C}basically\u{201D}",
                rule: "Cut filler intensifiers; let the verb carry the meaning.",
                frequency: 9, firstSeen: daysAgoRef(30, 10, 0), recency: daysAgoRef(1, 10, 0),
                status: .active,
                examples: [example(5, "basically just")]),
            RecurringPattern(
                lens: .pronunciation, key: "th-thorough",
                summary: "softens the /\u{03B8}/ in \u{201C}thorough\u{201D}",
                rule: "Tongue between the teeth for \u{201C}th\u{201D}.",
                frequency: 8, firstSeen: daysAgoRef(25, 10, 0), recency: daysAgoRef(2, 10, 0),
                status: .active,
                examples: [example(10, "a thorough review")]),
            RecurringPattern(
                lens: .discourse, key: "tighten-clause",
                summary: "stitches two ideas with a comma",
                rule: "Split into two sentences or use a clearer connective.",
                frequency: 4, firstSeen: daysAgoRef(20, 10, 0), recency: daysAgoRef(9, 10, 0),
                status: .improving,
                examples: [example(9, "completely")]),
            // Mastered: a real win — last recurred well over a month ago.
            RecurringPattern(
                lens: .prosody, key: "fillers-um-uh",
                summary: "leaned on \u{201C}um\u{201D} and \u{201C}uh\u{201D}",
                rule: "Replace fillers with a short silent pause.",
                frequency: 6, firstSeen: daysAgoRef(90, 10, 0), recency: daysAgoRef(45, 10, 0),
                status: .mastered,
                examples: [example(7, "um, the middle section")]),
        ]

        // CF-fix: the skill map now shows an evidence-grounded TREND, not a numeric
        // level — and the trend is derived from each lens's pattern status, so the
        // seed is self-consistent by construction:
        //   grammar  → "needs work"  (drop-articles is .active, recency today)
        //   lexis    → "needs work"  (overuse-basically is .active)
        //   pronunc. → "needs work"  (th-thorough is .active)
        //   discourse→ "improving"   (tighten-clause is .improving)
        //   prosody  → "improving"   (fillers-um-uh is .mastered — a win)
        // The `levels` below are kept only for the older Progress surface; the Coach
        // "This week" skill map no longer reads them, so they can't mislead the demo.
        var profile = LearnerProfile(
            inferredL1: "Mandarin",
            interferencePatterns: ["article omission", "final-consonant softening"],
            levels: [
                .grammar: 42,
                .lexis: 55,
                .discourse: 61,
                .pronunciation: 38,
                .prosody: 70,
            ],
            patterns: patterns,
            lexicalProfile: LexicalProfile(
                overusedWords: ["basically", "really", "just"],
                collocationGaps: ["make a payment", "reach a decision"],
                rangeNote: "Strong everyday range; reach for more precise verbs in formal contexts."),
            registerTendencies: ["slightly informal in written follow-ups"],
            goals: ["sound more concise in meetings", "clean up article use"],
            updatedAt: Date())

        // Recompute statuses/levels deterministically so the stored profile is
        // self-consistent with the seeded recencies (mirrors the real pipeline).
        profile.recomputeStatuses(asOf: Date())

        do {
            try profileStore.save(profile)
        } catch {
            log.error("DebugSeed: profile save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Seed a CoachSnapshot per note (objective signals) so growth trends + streak
    /// have a real dated history to plot. GOP improves slightly over time.
    private static func seedSnapshots(entries: [TranscriptEntry]) {
        var log = CoachSnapshotLog()
        let total = entries.count
        for (i, entry) in entries.enumerated() {
            let words = entry.text.split(whereSeparator: { $0 == " " }).count
            // Older notes (higher index = further back) score a bit worse, so the
            // trend reads as improvement toward the present.
            let progress = Double(total - i) / Double(max(total, 1))
            let snapshot = CoachSnapshot(
                noteID: entry.id,
                date: entry.date,
                durationSec: Double(words) / 2.4,
                wordCount: words,
                fillersPerMinute: 6.0 * (1.0 - progress) + 1.5,
                wordsPerMinute: 120 + progress * 25,
                longPauseRate: 0.18 * (1.0 - progress),
                restartCount: i % 3,
                hasPauseStats: true,
                overallGOP: -4.0 + progress * 2.2)
            log.upsert(snapshot)
        }
        do {
            try snapshotStore.save(log)
        } catch {
            self.log.error("DebugSeed: snapshot save failed: \(String(describing: error), privacy: .public)")
        }
    }
}

#endif
