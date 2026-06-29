import Foundation

/// CI-5 — keyless-first Review gating.
///
/// The Review feed is no longer gated on the presence of a BYOK key. The
/// objective lane (CI-2/CI-3/CI-4b) authors real pronunciation + fluency cards
/// with zero LLM, so the feed is non-empty for free. This pure helper decides
/// *which* shell state the view renders and whether to show the key upsell,
/// given a few booleans the view reads from SwiftData / preferences.
///
/// Keeping the decision pure means the rule ("never show the old key wall";
/// "upsell is non-blocking") is unit-tested in HexCore rather than tangled in
/// SwiftUI. See ADR-0002 ("Review can no longer gate on key presence").
public enum ReviewFeedGating {

    /// What the Review screen should render as its primary content.
    public enum FeedState: Equatable, Sendable {
        /// There are coaching cards to review — show the feed.
        case feed
        /// No cards right now, but the corpus has notes (objective analysis ran
        /// and found nothing actionable, or a refresh is pending) — "all caught up".
        case caughtUp
        /// Nothing has been captured/analyzed yet — first-run onboarding, NOT the
        /// old "connect a key" wall.
        case onboarding
    }

    /// The inputs the view can cheaply observe.
    public struct Inputs: Equatable, Sendable {
        /// At least one reviewable (`.new`) card exists in the feed.
        public var hasCards: Bool
        /// A usable BYOK key is present (coaching opted in + key stored).
        public var hasKey: Bool
        /// The learner has dictated at least one note (the corpus is non-empty).
        public var hasNotes: Bool

        public init(hasCards: Bool, hasKey: Bool, hasNotes: Bool) {
            self.hasCards = hasCards
            self.hasKey = hasKey
            self.hasNotes = hasNotes
        }
    }

    /// The primary content state. Cards always win (keyless-first): if the
    /// objective lane produced cards, we show them whether or not a key exists.
    public static func feedState(_ inputs: Inputs) -> FeedState {
        if inputs.hasCards { return .feed }
        // No cards. If the learner has notes, they've simply caught up. With no
        // notes at all, it's genuine first-run onboarding.
        return inputs.hasNotes ? .caughtUp : .onboarding
    }

    /// Whether to surface the non-blocking key upsell (banner/card). Shown
    /// whenever no key is present — it advertises the meaning + intonation lenses
    /// and richer LLM teaching without ever blocking the keyless feed.
    public static func showsKeyUpsell(_ inputs: Inputs) -> Bool {
        !inputs.hasKey
    }
}
