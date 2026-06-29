import Foundation

/// Pure decision logic for the two automatic analysis lanes (CI-7 / ADR-0004).
///
/// The lanes diverge by cost, so they gate differently:
///
/// - **Objective lane** is free + local, so it's *unconditionally on* at capture.
///   The only decision is idempotency: don't re-run if it already ran for a note.
/// - **LLM lane** is paid (BYOK), so it's automatic but **batched** (over a
///   backlog, never per-utterance), guarded by an on/off **toggle**, and hard
///   bounded by the monthly **budget** cap.
///
/// Kept pure + Sendable so the policy is deterministic and unit-testable without
/// touching SwiftData, the network, or the clock. The calling `CoachService`
/// owns the side effects (fetch, run, persist, record spend).
public enum CoachAutomation {
    // MARK: - Objective lane (free, local, always-on)

    /// Inputs the objective-lane auto-run decision depends on.
    public struct ObjectiveInputs: Sendable, Equatable {
        /// Whether this note has already had the objective lane run for it.
        public var alreadyAnalyzed: Bool

        public init(alreadyAnalyzed: Bool) {
            self.alreadyAnalyzed = alreadyAnalyzed
        }
    }

    /// Whether to run the free objective lane for a freshly-captured note.
    /// Always yes unless it already ran — the lane is free, so there's no key,
    /// toggle, or budget to consult, only idempotency.
    public static func shouldRunObjective(_ inputs: ObjectiveInputs) -> Bool {
        !inputs.alreadyAnalyzed
    }

    // MARK: - LLM lane (paid, BYOK, batched + capped + toggled)

    /// Inputs the LLM-lane auto-batch decision depends on.
    public struct LLMInputs: Sendable, Equatable {
        /// The user opted the Coach in *and* a usable BYOK key is present.
        public var isReady: Bool
        /// The LLM-lane automatic-analysis toggle is on (CI-7).
        public var autoEnabled: Bool
        /// A run isn't already in flight.
        public var isIdle: Bool
        /// There is un-analyzed work in the backlog to batch over.
        public var hasBacklog: Bool
        /// The monthly budget still allows spend this month.
        public var underBudget: Bool

        public init(
            isReady: Bool,
            autoEnabled: Bool,
            isIdle: Bool,
            hasBacklog: Bool,
            underBudget: Bool
        ) {
            self.isReady = isReady
            self.autoEnabled = autoEnabled
            self.isIdle = isIdle
            self.hasBacklog = hasBacklog
            self.underBudget = underBudget
        }
    }

    /// Whether to *automatically* kick off a batched LLM-lane run in the
    /// background. Requires opt-in + key, the auto toggle on, no run in flight,
    /// real backlog, and remaining budget — every gate must hold so automatic
    /// spend stays bounded and intentional.
    public static func shouldAutoRunLLM(_ inputs: LLMInputs) -> Bool {
        inputs.isReady
            && inputs.autoEnabled
            && inputs.isIdle
            && inputs.hasBacklog
            && inputs.underBudget
    }

    /// Whether the *manual* "Review now" override is offerable. Same as the
    /// automatic gate but independent of the toggle and of remaining budget —
    /// it's a user-initiated action, so the toggle doesn't suppress it, and the
    /// budget is still enforced inside the run itself (a run started at the cap
    /// simply does nothing). Surfaced only for keyed users with a backlog while
    /// no run is in flight.
    public static func showsManualOverride(_ inputs: LLMInputs) -> Bool {
        inputs.isReady && inputs.isIdle && inputs.hasBacklog
    }
}
