import Foundation

// MARK: - Card model

public enum CoachCardKind: String, Codable, Sendable {
    case improvement  // a more-natural rewrite of something you said
    case win          // a positive — a habit you've mastered
}

/// A single teachable moment for the Review feed (RC-3): your real words → a more
/// natural rewrite → the rule → which lens, or a positive "win". Derived from the
/// pipeline's `CoachInsight`s (CE-3) and the `LearnerProfile` (CE-2).
public struct CoachCard: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: CoachCardKind
    public var lens: Lens
    public var key: String
    public var title: String
    public var detail: String
    public var originalSpan: String?
    public var nativeRewrite: String?
    public var transcriptID: UUID?
    /// e.g. "Came up 4× — here's the pattern." Shown when an issue recurs.
    public var recurrenceNote: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: CoachCardKind,
        lens: Lens,
        key: String,
        title: String,
        detail: String,
        originalSpan: String? = nil,
        nativeRewrite: String? = nil,
        transcriptID: UUID? = nil,
        recurrenceNote: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.lens = lens
        self.key = key
        self.title = title
        self.detail = detail
        self.originalSpan = originalSpan
        self.nativeRewrite = nativeRewrite
        self.transcriptID = transcriptID
        self.recurrenceNote = recurrenceNote
        self.createdAt = createdAt
    }
}

// MARK: - Curation

/// Turns an analysis into a *small, deduped, positive-leaning* set of cards — not
/// one per mistake (RC-2). Pure, so volume/ordering is deterministic and tested.
public enum CoachCardCurator {
    public static func curate(
        analysis: CoachAnalysis,
        wins: [RecurringPattern],
        profile: LearnerProfile,
        now: Date,
        limit: Int = 5
    ) -> [CoachCard] {
        // Dedupe insights to one card per pattern key (keep the highest severity),
        // so a habit that recurred several times this batch is a single card.
        var byKey: [String: CoachInsight] = [:]
        for insight in analysis.insights {
            if let existing = byKey[insight.key], existing.severity >= insight.severity { continue }
            byKey[insight.key] = insight
        }

        let improvements = byKey.values
            .sorted { $0.severity > $1.severity }
            .map { insight -> CoachCard in
                let frequency = profile.patterns.first { $0.key == insight.key }?.frequency ?? 0
                let note = frequency >= 2 ? "Came up \(frequency)× — here's the pattern." : nil
                return CoachCard(
                    kind: .improvement, lens: insight.lens, key: insight.key,
                    title: insight.summary, detail: insight.rule,
                    originalSpan: insight.originalSpan, nativeRewrite: insight.nativeRewrite,
                    transcriptID: insight.transcriptID, recurrenceNote: note, createdAt: now
                )
            }

        let winCards = wins.map { pattern in
            CoachCard(
                kind: .win, lens: pattern.lens, key: pattern.key,
                title: "Mastered: \(pattern.summary)",
                detail: "You've stopped doing this — nice work.", createdAt: now
            )
        }

        // Positive-leaning: lead with a win when there is one, then the
        // improvements (highest-leverage first), then any remaining wins.
        var ordered: [CoachCard] = []
        if let firstWin = winCards.first { ordered.append(firstWin) }
        ordered.append(contentsOf: improvements)
        ordered.append(contentsOf: winCards.dropFirst())
        return Array(ordered.prefix(limit))
    }
}

// MARK: - Cost estimation (BYOK)

/// Rough USD estimate for a Gemini call so a BYOK user can see running cost
/// (RC-2 / CE-5). Pricing is approximate Gemini Developer API list pricing.
public enum CoachCostEstimator {
    /// USD per 1M tokens, (input, output).
    static func rate(for model: String) -> (input: Double, output: Double) {
        switch model {
        case GeminiClient.Model.flash: return (0.30, 2.50)
        case GeminiClient.Model.flashLite: return (0.10, 0.40)
        default: return (0.10, 0.40)
        }
    }

    public static func usd(promptTokens: Int, outputTokens: Int, model: String) -> Double {
        let rate = rate(for: model)
        return Double(promptTokens) / 1_000_000 * rate.input
            + Double(outputTokens) / 1_000_000 * rate.output
    }
}
