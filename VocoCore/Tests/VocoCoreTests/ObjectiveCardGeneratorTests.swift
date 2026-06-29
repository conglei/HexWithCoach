import XCTest
@testable import VocoCore

/// CI-4b: the deterministic, keyless objective → card generator. These tests use a
/// synthetic `TeachingContent` so they're fully deterministic and never touch the
/// network or the bundled assets' exact prose.
final class ObjectiveCardGeneratorTests: XCTestCase {

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let t2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    /// A small, hand-authored teaching content covering the phonemes/dimensions/L1
    /// the tests exercise.
    private func makeContent() -> TeachingContent {
        let phonemes = [
            PhonemeGuideEntry(
                ipa: "θ",
                exampleWord: "think",
                description: "The 'th' in think — a soft, unvoiced sound.",
                howToArticulate: "Put your tongue between your teeth and blow air.",
                commonL1Substitutions: ["s", "t"],
                practiceSentence: "I think this thing is thin.",
                minimalPair: "think / sink"
            ),
            PhonemeGuideEntry(
                ipa: "r",
                exampleWord: "red",
                description: "The English 'r' sound.",
                howToArticulate: "Curl your tongue back without touching the roof.",
                commonL1Substitutions: ["l"],
                practiceSentence: "The red car ran around.",
                minimalPair: "red / led"
            ),
        ]
        let tips = [
            FluencyTip(dimension: .fillers, title: "Trim the fillers",
                       tip: "Swap 'um' and 'uh' for a short silent pause."),
            FluencyTip(dimension: .longPauses, title: "Plan the clause",
                       tip: "Think the whole clause before you start saying it."),
            FluencyTip(dimension: .restarts, title: "Finish the thought",
                       tip: "Complete a sentence before reshaping it."),
            FluencyTip(dimension: .pace, title: "Steady pace",
                       tip: "Keep an even speaking rate."),
        ]
        let l1 = L1InterferenceTable(version: 1, languages: [
            L1InterferenceEntry(
                l1: "Mandarin", displayName: "Mandarin",
                interferencePhonemes: ["θ", "r"], note: "Mandarin lacks these."
            ),
        ])
        return TeachingContent(
            phonemeGuide: PhonemeGuide(version: 1, language: "en", phonemes: phonemes),
            fluencyTips: FluencyTips(version: 1, tips: tips),
            l1Interference: l1
        )
    }

    private func pronPattern(
        symbol: String, status: PatternStatus = .active, frequency: Int = 1,
        examples: [ExampleRef] = []
    ) -> RecurringPattern {
        RecurringPattern(
            lens: .pronunciation,
            key: PronunciationPatternDetector.key(forPhoneme: symbol),
            summary: "Recurring difficulty with /\(symbol)/",
            rule: "Practice /\(symbol)/.",
            frequency: frequency, firstSeen: now, recency: now, status: status,
            examples: examples
        )
    }

    private func fluencyPattern(
        kind: FluencyPatternDetector.Kind, status: PatternStatus = .active,
        frequency: Int = 1, examples: [ExampleRef] = []
    ) -> RecurringPattern {
        RecurringPattern(
            lens: .prosody,
            key: FluencyPatternDetector.key(for: kind),
            summary: "Recurring \(kind.rawValue)",
            rule: "Work on \(kind.rawValue).",
            frequency: frequency, firstSeen: now, recency: now, status: status,
            examples: examples
        )
    }

    // MARK: - Pronunciation pattern → card

    func testPronunciationPatternProducesCard() {
        let profile = LearnerProfile(patterns: [
            pronPattern(symbol: "θ", examples: [ExampleRef(transcriptID: t1, span: "think")]),
        ])
        let cards = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now)

        XCTAssertEqual(cards.count, 1)
        let card = try! XCTUnwrap(cards.first)
        XCTAssertEqual(card.lens, .pronunciation)
        XCTAssertEqual(card.kind, .improvement)
        XCTAssertEqual(card.origin, .objective)
        XCTAssertEqual(card.key, "pron-phoneme-θ")
        // Teaching content from the guide entry.
        XCTAssertTrue(card.detail.contains("tongue between your teeth"))
        XCTAssertTrue(card.detail.contains("think / sink"))  // minimal pair
        XCTAssertEqual(card.practiceText, "I think this thing is thin.")  // practice sentence
        XCTAssertEqual(card.transcriptID, t1)
    }

    func testPronunciationCardIncludesLearnersOwnExamples() {
        let profile = LearnerProfile(patterns: [
            pronPattern(symbol: "θ", examples: [
                ExampleRef(transcriptID: t1, span: "think"),
                ExampleRef(transcriptID: t2, span: "thing"),
            ]),
        ])
        let card = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now).first
        let span = try! XCTUnwrap(card?.originalSpan)
        XCTAssertTrue(span.contains("think"))
        XCTAssertTrue(span.contains("thing"))
    }

    func testUnknownPhonemeWithoutGuideEntryIsSkipped() {
        // ʒ has no entry in the synthetic content.
        let profile = LearnerProfile(patterns: [pronPattern(symbol: "ʒ")])
        let cards = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now)
        XCTAssertTrue(cards.isEmpty)
    }

    // MARK: - L1-aware substitution

    func testL1SubstitutionIncludedWhenL1Set() {
        let profile = LearnerProfile(
            inferredL1: "Mandarin",
            patterns: [pronPattern(symbol: "θ", examples: [ExampleRef(transcriptID: t1, span: "think")])]
        )
        let card = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now).first
        let detail = try! XCTUnwrap(card?.detail)
        // θ's first guide substitution that Mandarin interferes with is /s/.
        XCTAssertTrue(detail.contains("/s/"), "expected L1 substitution hint, got: \(detail)")
        XCTAssertTrue(detail.contains("first language"))
    }

    func testNoL1SubstitutionWhenL1Unset() {
        let profile = LearnerProfile(patterns: [pronPattern(symbol: "θ")])
        let card = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now).first
        let detail = try! XCTUnwrap(card?.detail)
        XCTAssertFalse(detail.contains("first language"))
    }

    func testNoL1SubstitutionWhenL1NotInTable() {
        let profile = LearnerProfile(
            inferredL1: "Klingon",
            patterns: [pronPattern(symbol: "θ")]
        )
        let card = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now).first
        XCTAssertFalse(try! XCTUnwrap(card?.detail).contains("first language"))
    }

    // MARK: - Fluency pattern → card

    func testFluencyPatternProducesCard() {
        let profile = LearnerProfile(patterns: [
            fluencyPattern(kind: .fillers, examples: [ExampleRef(transcriptID: t1, span: "5 fillers")]),
        ])
        let cards = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now)
        XCTAssertEqual(cards.count, 1)
        let card = try! XCTUnwrap(cards.first)
        XCTAssertEqual(card.lens, .prosody)
        XCTAssertEqual(card.origin, .objective)
        XCTAssertEqual(card.key, "fluency-fillers")
        XCTAssertEqual(card.title, "Trim the fillers")
        XCTAssertEqual(card.detail, "Swap 'um' and 'uh' for a short silent pause.")
        XCTAssertEqual(card.originalSpan, "5 fillers")
        XCTAssertEqual(card.transcriptID, t1)
    }

    func testFluencyPatternWithoutTipIsSkipped() {
        // A bogus fluency key with no matching dimension.
        let bogus = RecurringPattern(
            lens: .prosody, key: "fluency-bogus", summary: "x", rule: "y",
            firstSeen: now, recency: now, status: .active
        )
        let cards = ObjectiveCardGenerator.generate(profile: LearnerProfile(patterns: [bogus]),
                                                    content: makeContent(), now: now)
        XCTAssertTrue(cards.isEmpty)
    }

    // MARK: - Status filtering

    func testMasteredPatternsAreExcluded() {
        let profile = LearnerProfile(patterns: [
            pronPattern(symbol: "θ", status: .mastered),
            fluencyPattern(kind: .fillers, status: .mastered),
        ])
        let cards = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now)
        XCTAssertTrue(cards.isEmpty, "mastered patterns should not produce teaching cards")
    }

    func testImprovingPatternsStillProduceCards() {
        let profile = LearnerProfile(patterns: [pronPattern(symbol: "θ", status: .improving)])
        let cards = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now)
        XCTAssertEqual(cards.count, 1)
    }

    // MARK: - Ordering, dedup, determinism

    func testPronunciationCardsLeadFluencyCards() {
        let profile = LearnerProfile(patterns: [
            fluencyPattern(kind: .fillers),
            pronPattern(symbol: "r"),
            pronPattern(symbol: "θ"),
        ])
        let cards = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now)
        XCTAssertEqual(cards.map(\.lens), [.pronunciation, .pronunciation, .prosody])
    }

    func testDeterministicStableOrdering() {
        // Independent of pattern insertion order, output is sorted by key per lens.
        let p1 = LearnerProfile(patterns: [
            pronPattern(symbol: "r"), pronPattern(symbol: "θ"),
            fluencyPattern(kind: .restarts), fluencyPattern(kind: .fillers),
        ])
        let p2 = LearnerProfile(patterns: [
            fluencyPattern(kind: .fillers), pronPattern(symbol: "θ"),
            fluencyPattern(kind: .restarts), pronPattern(symbol: "r"),
        ])
        let content = makeContent()
        let keys1 = ObjectiveCardGenerator.generate(profile: p1, content: content, now: now).map(\.key)
        let keys2 = ObjectiveCardGenerator.generate(profile: p2, content: content, now: now).map(\.key)
        XCTAssertEqual(keys1, keys2)
        // pron-phoneme-r < pron-phoneme-θ (ASCII), then fluency-fillers < fluency-restarts.
        XCTAssertEqual(keys1, ["pron-phoneme-r", "pron-phoneme-θ", "fluency-fillers", "fluency-restarts"])
    }

    func testDuplicatePatternKeysProduceOneCard() {
        let profile = LearnerProfile(patterns: [
            pronPattern(symbol: "θ"),
            pronPattern(symbol: "θ"),
        ])
        let cards = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now)
        XCTAssertEqual(cards.count, 1)
    }

    // MARK: - Recurrence note

    func testRecurrenceNoteAppearsWhenFrequent() {
        let profile = LearnerProfile(patterns: [pronPattern(symbol: "θ", frequency: 4)])
        let card = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now).first
        XCTAssertEqual(card?.recurrenceNote, "Came up 4× — here's the pattern.")
    }

    func testNoRecurrenceNoteForSingleOccurrence() {
        let profile = LearnerProfile(patterns: [pronPattern(symbol: "θ", frequency: 1)])
        let card = ObjectiveCardGenerator.generate(profile: profile, content: makeContent(), now: now).first
        XCTAssertNil(card?.recurrenceNote)
    }

    // MARK: - Other lenses ignored

    func testNonObjectiveLensesAreIgnored() {
        let grammar = RecurringPattern(
            lens: .grammar, key: "drop-articles", summary: "x", rule: "y",
            firstSeen: now, recency: now, status: .active
        )
        let cards = ObjectiveCardGenerator.generate(profile: LearnerProfile(patterns: [grammar]),
                                                    content: makeContent(), now: now)
        XCTAssertTrue(cards.isEmpty)
    }

    // MARK: - Codable backward-compat (origin defaults to .llm)

    func testCardWithoutOriginDecodesAsLLM() throws {
        // Simulate an older persisted card JSON with no `origin` key.
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000AA","kind":"improvement","lens":"grammar",
         "key":"k","title":"t","detail":"d","createdAt":\(now.timeIntervalSinceReferenceDate)}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let card = try decoder.decode(CoachCard.self, from: json)
        XCTAssertEqual(card.origin, .llm)
    }
}
