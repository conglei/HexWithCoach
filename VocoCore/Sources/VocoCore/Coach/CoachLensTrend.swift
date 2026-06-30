//
//  CoachLensTrend.swift
//  VocoCore
//
//  CF-fix — the per-lens *trend* that replaces the ungrounded numeric "level" on
//  the Coach skill map. A fluent speaker doesn't need a 0–100 score (which the
//  profile assigned arbitrarily — DebugSeed put grammar at 42 while an article-drop
//  pattern was actively recurring, so the number contradicted the data). A trend is
//  honest because it is derived ONLY from the lens's real pattern signal:
//
//    .needsWork  — the lens has at least one ACTIVE (still-recurring) pattern.
//    .improving  — no active pattern, but the lens has a mastered/improving one
//                  (net forward motion).
//    .steady     — the lens has signal but nothing active and nothing to celebrate,
//                  OR there is simply nothing measured yet (holding, never negative).
//
//  Pure + deterministic so it's fast-testable in `swift test`, and so the skill-map
//  UI and the LLM-recap grounding read exactly the same trend.
//

import Foundation

/// The growth-framed, evidence-grounded direction for one lens on the skill map.
/// Distinct from `ProgressSummary.Trend` (which has a `.new` "nothing yet" case and
/// only ever reads `improving`/`steady`): this adds an honest `.needsWork` driven by
/// an actively-recurring pattern, so the map can no longer say "grammar: steady"
/// while a drop-articles pattern is live.
public enum CoachLensTrend: String, Sendable, Equatable, CaseIterable {
    /// Net forward motion — a mastered/improving pattern and nothing actively recurring.
    case improving
    /// Holding — signal exists but nothing actively recurring and nothing to celebrate,
    /// or nothing measured yet. Never reads as a downgrade.
    case steady
    /// At least one pattern is still actively recurring in this lens.
    case needsWork

    /// The SF Symbol the skill-map row renders for this trend.
    public var systemImage: String {
        switch self {
        case .improving: "arrow.up.right"
        case .steady: "arrow.right"
        case .needsWork: "arrow.down.right"
        }
    }

    /// A short label for the row + the (number-free) LLM grounding data block.
    public var label: String {
        switch self {
        case .improving: "improving"
        case .steady: "steady"
        case .needsWork: "needs work"
        }
    }
}

public extension CoachLensTrend {
    /// Derive the trend for a lens purely from its patterns. Grounded in the real
    /// signal: an active pattern → `.needsWork`; else a win/improving pattern →
    /// `.improving`; else `.steady`. Deterministic — same patterns in, same trend out.
    static func make(lens: Lens, patterns: [RecurringPattern]) -> CoachLensTrend {
        let forLens = patterns.filter { $0.lens == lens }
        if forLens.contains(where: { $0.status == .active }) {
            return .needsWork
        }
        if forLens.contains(where: { $0.status == .mastered || $0.status == .improving }) {
            return .improving
        }
        return .steady
    }
}
