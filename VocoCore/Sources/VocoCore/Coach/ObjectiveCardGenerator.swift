import Foundation

/// Turns the learner's objective ``RecurringPattern``s (pronunciation phonemes
/// from CI-3, fluency habits from CI-2) into ``CoachCard``s with **zero LLM and
/// zero network** — the keyless half of the coach (CI-4b, ADR-0002 §"objective
/// lenses need a deterministic teaching layer").
///
/// Teaching prose comes entirely from the bundled ``TeachingContent`` (phoneme
/// guide + fluency-tips table); personalization comes from the learner's own
/// flagged examples carried on each pattern. When a BYOK key is present the LLM
/// lane *enriches* these `.objective` cards — it does not replace them, and the
/// `origin` field lets enrichment target them (ADR-0001 refinement).
///
/// Pure and deterministic: the same profile + content in always produces the same
/// cards out, in a stable order, with no duplicates. No I/O, no clock except the
/// caller-supplied `now`.
public enum ObjectiveCardGenerator {

    /// The pronunciation pattern key prefix (mirrors
    /// `PronunciationPatternDetector.key(forPhoneme:)`).
    public static let pronunciationKeyPrefix = "pron-phoneme-"
    /// The fluency pattern key prefix (mirrors `FluencyPatternDetector.key(for:)`).
    public static let fluencyKeyPrefix = "fluency-"

    /// Build keyless objective cards from a learner profile.
    ///
    /// - Parameters:
    ///   - profile: the learner's profile (only pronunciation/prosody patterns are read).
    ///   - content: the bundled teaching assets (defaults to the shared instance).
    ///   - now: the card creation timestamp (injected so output is deterministic).
    /// - Returns: deduped cards, pronunciation first then fluency, each in a
    ///   stable order. A pattern with no matching guide/tip entry is skipped.
    public static func generate(
        profile: LearnerProfile,
        content: TeachingContent = .default,
        now: Date
    ) -> [CoachCard] {
        var cards: [CoachCard] = []
        var seenKeys = Set<String>()

        func appendUnique(_ card: CoachCard?) {
            guard let card, seenKeys.insert(card.key).inserted else { return }
            cards.append(card)
        }

        // Pronunciation cards (lens .pronunciation), sorted by key for stable order.
        let pronPatterns = activePatterns(in: profile, lens: .pronunciation)
            .sorted { $0.key < $1.key }
        for pattern in pronPatterns {
            appendUnique(pronunciationCard(for: pattern, profile: profile, content: content, now: now))
        }

        // Fluency cards (lens .prosody), sorted by key for stable order.
        let fluencyPatterns = activePatterns(in: profile, lens: .prosody)
            .sorted { $0.key < $1.key }
        for pattern in fluencyPatterns {
            appendUnique(fluencyCard(for: pattern, content: content, now: now))
        }

        return cards
    }

    // MARK: - Status filter

    /// Patterns for a lens that should produce a card: `.active` or `.improving`,
    /// never `.mastered` (a mastered habit is a win, not a thing to teach).
    private static func activePatterns(in profile: LearnerProfile, lens: Lens) -> [RecurringPattern] {
        profile.patterns.filter { $0.lens == lens && $0.status != .mastered }
    }

    // MARK: - Pronunciation

    static func pronunciationCard(
        for pattern: RecurringPattern,
        profile: LearnerProfile,
        content: TeachingContent,
        now: Date
    ) -> CoachCard? {
        guard pattern.key.hasPrefix(pronunciationKeyPrefix) else { return nil }
        let symbol = String(pattern.key.dropFirst(pronunciationKeyPrefix.count))
        guard !symbol.isEmpty, let entry = content.phoneme(symbol) else { return nil }

        // The learner's own flagged example words for this phoneme.
        let exampleWords = orderedExampleSpans(pattern.examples)

        var detail = "\(entry.description) \(entry.howToArticulate)"
        if let substitution = l1Substitution(symbol: symbol, entry: entry, profile: profile, content: content) {
            detail += " Speakers of your first language often say /\(substitution)/ instead — listen for that swap."
        }
        detail += " Minimal pair: \(entry.minimalPair)."

        let title = "The /\(symbol)/ sound — like in \"\(entry.exampleWord)\""
        let recurrenceNote = recurrenceNote(for: pattern)

        // Lead the span with the learner's own words when we have them, so the
        // card is grounded in their corpus rather than a generic example.
        let originalSpan = exampleWords.isEmpty ? nil : exampleWords.joined(separator: ", ")

        return CoachCard(
            kind: .improvement,
            lens: .pronunciation,
            key: pattern.key,
            title: title,
            detail: detail,
            originalSpan: originalSpan,
            nativeRewrite: nil,
            context: nil,
            practiceText: entry.practiceSentence,
            transcriptID: pattern.examples.first?.transcriptID,
            recurrenceNote: recurrenceNote,
            createdAt: now,
            origin: .objective
        )
    }

    /// The common substitution to surface for a phoneme, but only when the
    /// learner's L1 is known to interfere with *this* phoneme (it's in the L1's
    /// interference list) and the guide records a substitution for it. Returns the
    /// guide's first listed substitution (most common) in that case; nil otherwise.
    /// L1 is a booster, never a gate (ADR-0003) — without it we simply omit the hint.
    private static func l1Substitution(
        symbol: String,
        entry: PhonemeGuideEntry,
        profile: LearnerProfile,
        content: TeachingContent
    ) -> String? {
        guard let l1 = profile.inferredL1,
              let interference = content.interference(forL1: l1),
              interference.interferencePhonemes.contains(symbol)
        else { return nil }
        return entry.commonL1Substitutions.first
    }

    // MARK: - Fluency

    static func fluencyCard(
        for pattern: RecurringPattern,
        content: TeachingContent,
        now: Date
    ) -> CoachCard? {
        guard pattern.key.hasPrefix(fluencyKeyPrefix) else { return nil }
        let dimensionRaw = String(pattern.key.dropFirst(fluencyKeyPrefix.count))
        guard let dimension = FluencyDimension(rawValue: dimensionRaw),
              let tip = content.tip(for: dimension)
        else { return nil }

        let exampleSpans = orderedExampleSpans(pattern.examples)
        let originalSpan = exampleSpans.isEmpty ? nil : exampleSpans.joined(separator: ", ")

        return CoachCard(
            kind: .improvement,
            lens: .prosody,
            key: pattern.key,
            title: tip.title,
            detail: tip.tip,
            originalSpan: originalSpan,
            nativeRewrite: nil,
            context: nil,
            practiceText: nil,
            transcriptID: pattern.examples.first?.transcriptID,
            recurrenceNote: recurrenceNote(for: pattern),
            createdAt: now,
            origin: .objective
        )
    }

    // MARK: - Shared helpers

    /// The learner's own example spans in stored order, deduped, blanks dropped.
    private static func orderedExampleSpans(_ examples: [ExampleRef]) -> [String] {
        var seen = Set<String>()
        return examples
            .map { $0.span.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// "Came up 4× — here's the pattern." when a habit recurred; nil otherwise.
    private static func recurrenceNote(for pattern: RecurringPattern) -> String? {
        pattern.frequency >= 2 ? "Came up \(pattern.frequency)× — here's the pattern." : nil
    }
}
