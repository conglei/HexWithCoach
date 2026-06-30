import Foundation
import Testing
@testable import VocoCore

/// CF-1 — the pure ranking + skill-map + template-summary engine. The load-bearing
/// assertion (issue Verify): with seeded-style findings, the lens weighting must
/// make a high-VALUE-lens item (lexis/discourse/prosody) outrank a
/// high-FREQUENCY-but-low-value one (dropped articles / pronunciation), and the
/// evidence bar must keep trivia off a fluent user's surface entirely.
struct CoachFocusTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Mirrors the seed harness: drop-articles 12× (grammar), overuse-basically 9×
    /// (lexis), /θ/ 8× (pronunciation), tighten-clause 4× (discourse).
    private func seededFacts() -> [ObservationFact] {
        var facts: [ObservationFact] = []
        func cluster(_ lens: Lens, _ key: String, _ count: Int, sev: Int, span: String) {
            for i in 0..<count {
                facts.append(ObservationFact(
                    lens: lens, key: key, severity: sev,
                    date: now.addingTimeInterval(-Double(i) * 24 * 3600 / 2), span: span))
            }
        }
        cluster(.grammar, "drop-articles", 12, sev: 3, span: "send to design team")
        cluster(.lexis, "overuse-basically", 9, sev: 2, span: "basically just")
        cluster(.pronunciation, "th-thorough", 8, sev: 3, span: "a thorough review")
        cluster(.discourse, "tighten-clause", 4, sev: 2, span: "completely changed")
        return facts
    }

    private func seededProfile() -> LearnerProfile {
        func pat(_ lens: Lens, _ key: String, _ summary: String, _ freq: Int, status: PatternStatus = .active, recencyDaysAgo: Int = 1) -> RecurringPattern {
            RecurringPattern(
                lens: lens, key: key, summary: summary, rule: "rule",
                frequency: freq, firstSeen: now.addingTimeInterval(-40 * 24 * 3600),
                recency: now.addingTimeInterval(-Double(recencyDaysAgo) * 24 * 3600), status: status)
        }
        return LearnerProfile(
            levels: [.grammar: 42, .lexis: 55, .discourse: 61, .pronunciation: 38, .prosody: 70],
            patterns: [
                pat(.grammar, "drop-articles", "drops articles before nouns", 12),
                pat(.lexis, "overuse-basically", "overuses “basically”", 9),
                pat(.pronunciation, "th-thorough", "softens the /θ/ in “thorough”", 8),
                pat(.discourse, "tighten-clause", "stitches two ideas with a comma", 4, status: .improving, recencyDaysAgo: 9),
                pat(.prosody, "fillers-um-uh", "leaned on “um” and “uh”", 6, status: .mastered, recencyDaysAgo: 45),
            ])
    }

    // MARK: - Ranking calibration

    @Test
    func lexisOutranksHigherFrequencyArticleDrop() {
        let surface = CoachFocusEngine.surface(
            facts: seededFacts(), profile: seededProfile(), now: now)
        let hero = surface.heroFocus
        #expect(hero != nil)
        // Lexis (9×) must lead, NOT grammar's article-drop (12×): the comfortable
        // speaker is steered to naturalness, not error drills.
        #expect(hero?.lens == .lexis)
        #expect(hero?.key == "overuse-basically")
    }

    @Test
    func articleDropIsBelowEvidenceBarForFluentUser() {
        let surface = CoachFocusEngine.surface(
            facts: seededFacts(), profile: seededProfile(), now: now)
        // Despite the highest raw frequency, dropped articles must not be surfaced —
        // flagging it to a fluent speaker is trivia. The low lens weight pushes its
        // priority below the bar.
        #expect(!surface.focuses.contains { $0.key == "drop-articles" })
        #expect(!surface.focuses.contains { $0.key == "th-thorough" })
    }

    @Test
    func priorityProductHonoursLensWeightOverRawFrequency() {
        let policy = FocusRankingPolicy.default
        let p = ProgressSummary.make(profile: seededProfile(), streak: StreakState())
        let lexis = CoachFocusEngine.priorityScore(
            frequency: 9, severity: 2, lens: .lexis, latest: now,
            trend: p.progress(for: .lexis)?.trend ?? .steady, now: now, policy: policy)
        let grammar = CoachFocusEngine.priorityScore(
            frequency: 12, severity: 3, lens: .grammar, latest: now,
            trend: p.progress(for: .grammar)?.trend ?? .steady, now: now, policy: policy)
        #expect(lexis > grammar)
    }

    @Test
    func evidenceThresholdHidesLowFrequencyNoise() {
        // A single occurrence in a high-value lens still doesn't surface — precision
        // over recall (min frequency 2).
        let facts = [ObservationFact(lens: .lexis, key: "one-off", severity: 5, date: now, span: "x")]
        let surface = CoachFocusEngine.surface(facts: facts, profile: LearnerProfile(), now: now)
        #expect(surface.focuses.isEmpty)
    }

    @Test
    func surfaceCapsFocusesAndOrdersByPriority() {
        // Three high-value-lens clusters all clear the bar; only the top maxFocuses
        // survive, highest priority first.
        var facts: [ObservationFact] = []
        for (lens, key) in [(Lens.lexis, "a"), (.discourse, "b"), (.prosody, "c"), (.lexis, "d")] {
            for i in 0..<8 { facts.append(ObservationFact(lens: lens, key: key, severity: 3, date: now.addingTimeInterval(-Double(i) * 3600), span: "s")) }
        }
        let surface = CoachFocusEngine.surface(facts: facts, profile: LearnerProfile(), now: now)
        #expect(surface.focuses.count <= FocusRankingPolicy.default.maxFocuses)
        // Sorted descending by priority.
        let priorities = surface.focuses.map(\.priority)
        #expect(priorities == priorities.sorted(by: >))
    }

    // MARK: - Skill map

    @Test
    func skillMapHasAllFiveLensesInOrderWithGroundedTrends() {
        let surface = CoachFocusEngine.surface(facts: [], profile: seededProfile(), now: now)
        #expect(surface.skillMap.map(\.lens) == Lens.allCases)
        // CF-fix: the map shows a grounded trend, not a numeric level.
        // Prosody has a mastered pattern (and no active) → improving.
        #expect(surface.skillMap.first { $0.lens == .prosody }?.trend == .improving)
        // Grammar has an ACTIVE drop-articles pattern → needs work, NOT high/steady.
        #expect(surface.skillMap.first { $0.lens == .grammar }?.trend == .needsWork)
        // Discourse's only pattern is improving (no active) → improving.
        #expect(surface.skillMap.first { $0.lens == .discourse }?.trend == .improving)
    }

    @Test
    func leadWinIsTheMostRecentlyMasteredPattern() {
        let surface = CoachFocusEngine.surface(facts: seededFacts(), profile: seededProfile(), now: now)
        #expect(surface.leadWin?.key == "fillers-um-uh")
    }

    // MARK: - Practice routing

    @Test
    func heroFocusRoutesToMatchedDrill() {
        let surface = CoachFocusEngine.surface(facts: seededFacts(), profile: seededProfile(), now: now)
        // Lexis → wordSwap (CF-2 routing).
        #expect(surface.heroFocus?.practiceKind == .wordSwap)
    }

    // MARK: - Deterministic stats block (numbers computed by us, never the LLM)

    @Test
    func statsComputeMinutesNotesAndFillerDeltaFromWeekly() {
        let weekly = [
            CoachWeeklyRollup(weekStart: now.addingTimeInterval(-14 * 24 * 3600), noteCount: 5,
                              totalDurationSec: 1800, meanFillersPerMinute: 4.5, meanWordsPerMinute: 120, meanLongPauseRate: 0.1, meanGOP: nil),
            CoachWeeklyRollup(weekStart: now.addingTimeInterval(-7 * 24 * 3600), noteCount: 7,
                              totalDurationSec: 2400, meanFillersPerMinute: 3.0, meanWordsPerMinute: 130, meanLongPauseRate: 0.08, meanGOP: nil),
        ]
        let stats = CoachStats.make(weekly: weekly)
        #expect(stats.minutesSpoken == 40)              // 2400 / 60
        #expect(stats.noteCount == 7)
        #expect(stats.fillersPerMinute == 3.0)
        #expect(stats.fillersPerMinuteDelta == -1.5)    // 3.0 - 4.5 (improvement)
    }

    // MARK: - Number-free recap input + template

    private func sampleRecapInput() -> CoachRecapInput {
        let surface = CoachFocusEngine.surface(facts: seededFacts(), profile: seededProfile(), now: now)
        return CoachRecapInput.make(surface: surface)
    }

    @Test
    func recapInputIsNumberFree() {
        let input = sampleRecapInput()
        // No field on the input can carry a count/level/duration — the type literally
        // has no numeric fields. Assert the findings exist and carry only phrasing.
        #expect(!input.findings.isEmpty)
        // The hero is lexis (word choice) per the ranking calibration.
        #expect(input.findings.first?.lens == .lexis)
        // Lens trends are grounded words, not numbers.
        #expect(input.lensTrends.first { $0.lens == .grammar }?.trend == .needsWork)
    }

    @Test
    func templateRecapTalksAboutFocusWithoutNumbers() {
        let text = CoachRecapTemplate.render(sampleRecapInput())
        #expect(text.lowercased().contains("word choice"))
        // The deterministic recap is itself number-free.
        #expect(text.rangeOfCharacter(from: .decimalDigits) == nil)
    }

    @Test
    func templateRecapEmptyFindingsIsHonestNeverFabricated() {
        let empty = CoachRecapInput(lensTrends: [], findings: [], leadWinPhrase: nil)
        let text = CoachRecapTemplate.render(empty)
        #expect(text == CoachRecapTemplate.emptyLine)
        // The honest line the issue requires; never invented perfection.
        #expect(text.lowercased().contains("nothing stands out"))
        #expect(!text.lowercased().contains("flawless"))
        #expect(!text.lowercased().contains("level"))
    }

    @Test
    func recapPromptCarriesNoNumbersAndForbidsThem() {
        let prompt = CoachRecapPrompt.userPrompt(sampleRecapInput())
        // The number-free data block must NOT contain any digit.
        #expect(prompt.rangeOfCharacter(from: .decimalDigits) == nil)
        // The system rules forbid numbers + invention + perfection.
        #expect(CoachRecapPrompt.system.contains("Do NOT state ANY number"))
        #expect(CoachRecapPrompt.system.contains("Do NOT invent"))
        #expect(CoachRecapPrompt.system.contains("Never claim perfection"))
    }

    // MARK: - Grounded generator: empty path, validator gate, fallback

    private struct FailingLLM: CoachLLM {
        func generateJSON(systemPrompt: String, userPrompt: String, audio: CoachAudio?, tier: CoachModelTier) async throws -> String {
            struct E: Error {}
            throw E()
        }
    }

    private struct EchoLLM: CoachLLM {
        let response: String
        func generateJSON(systemPrompt: String, userPrompt: String, audio: CoachAudio?, tier: CoachModelTier) async throws -> String {
            response
        }
    }

    /// A finding-bearing input so the generator actually calls the LLM.
    private func validatableInput() -> CoachRecapInput {
        CoachRecapInput(
            lensTrends: [(.lexis, .needsWork), (.grammar, .needsWork)],
            findings: [CoachRecapInput.Finding(lens: .lexis, phrase: "overuses “basically”", trend: .needsWork, example: "basically just")],
            leadWinPhrase: nil)
    }

    @Test
    func emptyFindingsNeverCallsLLMAndReturnsHonestTemplate() async {
        // Even WITH an LLM available, empty findings must not call it — that was the
        // fabrication point ("flawless / level 10").
        let gen = CoachWeeklySummaryGenerator(llm: EchoLLM(response: "You are flawless, level 10."))
        let empty = CoachRecapInput(lensTrends: [], findings: [], leadWinPhrase: nil)
        let result = await gen.generate(empty)
        #expect(result.source == .template)
        #expect(result.text == CoachRecapTemplate.emptyLine)
    }

    @Test
    func keylessGeneratorUsesTemplate() async {
        let gen = CoachWeeklySummaryGenerator(llm: nil)
        let result = await gen.generate(validatableInput())
        #expect(result.source == .template)
        #expect(!result.text.isEmpty)
    }

    @Test
    func llmErrorFallsBackToTemplate() async {
        let gen = CoachWeeklySummaryGenerator(llm: FailingLLM())
        let result = await gen.generate(validatableInput())
        #expect(result.source == .template)
    }

    @Test
    func validGroundedProseIsUsed() async {
        let gen = CoachWeeklySummaryGenerator(
            llm: EchoLLM(response: "Your word choice is the place to refine next, and it's worth a little attention."))
        let result = await gen.generate(validatableInput())
        #expect(result.source == .llm)
    }

    @Test
    func fabricatedLevelTenRecapIsRejectedAndFallsBack() async {
        // The exact failure the issue calls out: the model returns "flawless level 10".
        // The validator must catch the leaked number → template fallback.
        let gen = CoachWeeklySummaryGenerator(
            llm: EchoLLM(response: "You're flawless — level 10 across the board."))
        let result = await gen.generate(validatableInput())
        #expect(result.source == .template)
    }

    @Test
    func llmJSONWrappedProseIsExtracted() async {
        let gen = CoachWeeklySummaryGenerator(
            llm: EchoLLM(response: "{\"summary\": \"Tighten your word choice and you'll sound sharper.\"}"))
        let result = await gen.generate(validatableInput())
        #expect(result.source == .llm)
        #expect(result.text == "Tighten your word choice and you'll sound sharper.")
    }

    // MARK: - CoachPaths (single source of truth for the Coach directory)

    @Test
    func coachPathsAppendsCoachOnNilContainerBranch() {
        // The bug this guards against: when the App Group container is nil
        // (no-entitlement sim / tests), callers that drop "Coach" on the fallback
        // branch land in `<temp>/` while others land in `<temp>/Coach`, so a writer
        // and a reader silently disagree. `CoachPaths` must append "Coach" on BOTH
        // branches. A bogus group id guarantees the container is nil.
        let dir = CoachPaths.directory(appGroupIdentifier: "group.invalid.nonexistent")
        #expect(dir.lastPathComponent == "Coach")
        let profile = CoachPaths.profileURL(appGroupIdentifier: "group.invalid.nonexistent")
        #expect(profile.lastPathComponent == "profile.json")
        #expect(profile.deletingLastPathComponent().lastPathComponent == "Coach")
        let snaps = CoachPaths.snapshotsURL(appGroupIdentifier: "group.invalid.nonexistent")
        #expect(snaps.lastPathComponent == "snapshots.json")
        #expect(snaps.deletingLastPathComponent().lastPathComponent == "Coach")
    }

    @Test
    func coachPathsProfileAndSnapshotsShareOneDirectory() {
        // Both files must live in the SAME directory so a single reader finds both —
        // the whole point of one source of truth.
        let profile = CoachPaths.profileURL(appGroupIdentifier: "group.invalid.nonexistent")
        let snaps = CoachPaths.snapshotsURL(appGroupIdentifier: "group.invalid.nonexistent")
        #expect(profile.deletingLastPathComponent() == snaps.deletingLastPathComponent())
        #expect(profile.deletingLastPathComponent() == CoachPaths.directory(appGroupIdentifier: "group.invalid.nonexistent"))
    }
}
