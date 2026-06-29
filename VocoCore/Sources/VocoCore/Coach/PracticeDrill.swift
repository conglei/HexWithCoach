//
//  PracticeDrill.swift
//  VocoCore
//
//  CF-2 — the typed practice framework. Practice used to be *only* shadowing
//  ("hear → say → GOP"), which fits pronunciation/prosody but not the lenses where
//  the learning is in the *choice*, not the mouth. This file generalizes practice
//  into a small family of drills, each matched to a lens, and — critically — lets
//  the system pick the right one from the focus area's lens so the user never has
//  to choose a drill type.
//
//  Everything here is pure (no UIKit / SwiftData / network) so the selection and
//  the word-swap judge are fast-testable in `swift test`. The SwiftUI surfaces
//  (ShadowingView, WordSwapView) are the *interaction* layer that renders a drill
//  and records the attempt; they live in the app target.
//

import Foundation

// MARK: - Drill kind

/// The kind of practice drill. The kind is chosen from a focus area's `Lens` (see
/// `PracticeKind.forLens`) — the user never picks it. Adding a new kind is a new
/// `case` + a new `PracticeDrill` conformer, not a rewrite of the practice surface.
///
/// Persisted on `PracticeItem.kind` (raw value) so every recorded attempt is
/// tagged with the drill it came from (feeds CF-3's per-kind progress).
public enum PracticeKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Hear the natural phrasing, then say it back — scored by ASR match + GOP.
    /// The pronunciation / prosody drill (RC-4 / SR-2). **Exists.**
    case shadow
    /// Produce a more natural word / phrase for a span you said — scored by a
    /// heuristic (did you produce the target or an acceptable variant). The
    /// vocabulary drill — the highest-value polish drill for a fluent speaker.
    case wordSwap

    // Reserved for follow-up issues (each a new conformer, not a rewrite):
    //   case reSayClean   // fluency  — re-speak minimizing fillers / pace
    //   case fixForm      // grammar  — produce the corrected form
    //   case condense     // clarity  — say it shorter & clearer vs a model

    /// The drill that fits a focus area's lens. This is what makes focus
    /// effortless: launching practice on a card maps the card's lens to its drill.
    ///
    /// - lexis → `wordSwap` (the learning is the word choice, not the sounds).
    /// - everything else → `shadow` until its own conformer ships (grammar /
    ///   discourse / prosody fall back to shadowing the corrected sentence, which
    ///   at least rehearses the better phrasing; their dedicated drills are
    ///   follow-up issues).
    public static func forLens(_ lens: Lens) -> PracticeKind {
        switch lens {
        case .lexis:
            return .wordSwap
        case .pronunciation, .prosody, .grammar, .discourse:
            return .shadow
        }
    }
}

// MARK: - Drill abstraction

/// A typed practice drill = `{ content, interaction, scoring }`. The `content` is
/// derived from a coach card / `CoachInsight`; the `interaction` is the kind
/// (which view renders it); the `score(production:)` turns what the learner
/// produced into a 0…1 signal + respectful feedback.
///
/// `shadow` and `wordSwap` are the two conformers today. A scored drill must
/// degrade gracefully with no network — both score on-device.
public protocol PracticeDrill: Sendable {
    /// Which interaction renders + records this drill.
    var kind: PracticeKind { get }
    /// The drill's content, derived from a card / insight.
    var content: PracticeDrillContent { get }
    /// Score what the learner produced (their spoken / typed attempt) against the
    /// drill's target. Pure + on-device; never blocks on the network.
    func score(production: String) -> DrillScore
}

/// The content a drill presents, derived from a `CoachInsight` / coach card. Not
/// every field applies to every kind: `shadow` only needs `target`; `wordSwap`
/// uses `originalSpan` (what you said) → `nativeRewrite` (the natural choice).
public struct PracticeDrillContent: Sendable, Equatable {
    /// Short display title (the card's title / rule summary).
    public var title: String
    /// The natural, speakable sentence — the shadow target / the model answer.
    public var target: String
    /// The verbatim span the learner originally said (the "before"). nil for
    /// pasted text with no source.
    public var originalSpan: String?
    /// The more-natural rewrite of `originalSpan` (the "after"). The thing the
    /// learner must *produce* in a `wordSwap` drill.
    public var nativeRewrite: String?
    /// The full sentence the span came from — context for the warm-up.
    public var context: String?
    /// Which lens this drill addresses (drives copy + the chosen kind).
    public var lens: Lens

    public init(
        title: String,
        target: String,
        originalSpan: String? = nil,
        nativeRewrite: String? = nil,
        context: String? = nil,
        lens: Lens
    ) {
        self.title = title
        self.target = target
        self.originalSpan = originalSpan
        self.nativeRewrite = nativeRewrite
        self.context = context
        self.lens = lens
    }
}

/// A drill attempt's outcome: a 0…1 score, whether it clears the kind's bar, and a
/// short, respectful, non-punitive feedback line ("the native choice here is X"),
/// never a harsh "wrong".
public struct DrillScore: Sendable, Equatable {
    /// 0…1 quality of the production.
    public var value: Double
    /// Whether the production cleared the drill's "good enough" bar.
    public var isWin: Bool
    /// One short, encouraging line to show the learner.
    public var feedback: String

    public init(value: Double, isWin: Bool, feedback: String) {
        self.value = value
        self.isWin = isWin
        self.feedback = feedback
    }
}
