import Foundation
import Testing
@testable import HexCore

/// TDD for CI-7: the pure two-lane automation policy. The objective lane is free
/// + always-on (idempotent), the LLM lane is automatic but gated by key, toggle,
/// idleness, backlog, and budget.
struct CoachAutomationTests {
    // MARK: - Objective lane

    @Test func objectiveRunsWhenNotYetAnalyzed() {
        #expect(CoachAutomation.shouldRunObjective(.init(alreadyAnalyzed: false)))
    }

    @Test func objectiveSkipsWhenAlreadyAnalyzed() {
        #expect(!CoachAutomation.shouldRunObjective(.init(alreadyAnalyzed: true)))
    }

    // MARK: - LLM lane: auto-run

    private func llmInputs(
        isReady: Bool = true,
        autoEnabled: Bool = true,
        isIdle: Bool = true,
        hasBacklog: Bool = true,
        underBudget: Bool = true
    ) -> CoachAutomation.LLMInputs {
        .init(isReady: isReady, autoEnabled: autoEnabled, isIdle: isIdle, hasBacklog: hasBacklog, underBudget: underBudget)
    }

    @Test func autoRunsWhenAllGatesHold() {
        #expect(CoachAutomation.shouldAutoRunLLM(llmInputs()))
    }

    @Test func autoBlockedWithoutKey() {
        #expect(!CoachAutomation.shouldAutoRunLLM(llmInputs(isReady: false)))
    }

    @Test func autoBlockedWhenToggleOff() {
        #expect(!CoachAutomation.shouldAutoRunLLM(llmInputs(autoEnabled: false)))
    }

    @Test func autoBlockedWhenBusy() {
        #expect(!CoachAutomation.shouldAutoRunLLM(llmInputs(isIdle: false)))
    }

    @Test func autoBlockedWithEmptyBacklog() {
        #expect(!CoachAutomation.shouldAutoRunLLM(llmInputs(hasBacklog: false)))
    }

    @Test func autoBlockedWhenOverBudget() {
        // The budget cap is load-bearing: it must bound *automatic* spend.
        #expect(!CoachAutomation.shouldAutoRunLLM(llmInputs(underBudget: false)))
    }

    // MARK: - LLM lane: manual override

    @Test func manualOverrideOfferedForKeyedUserWithBacklog() {
        #expect(CoachAutomation.showsManualOverride(llmInputs()))
    }

    @Test func manualOverrideIgnoresToggleAndBudget() {
        // The override stays available even when auto is off and the cap is hit;
        // the run itself still enforces the budget.
        #expect(CoachAutomation.showsManualOverride(llmInputs(autoEnabled: false, underBudget: false)))
    }

    @Test func manualOverrideHiddenWithoutKey() {
        #expect(!CoachAutomation.showsManualOverride(llmInputs(isReady: false)))
    }

    @Test func manualOverrideHiddenWhenBusy() {
        #expect(!CoachAutomation.showsManualOverride(llmInputs(isIdle: false)))
    }

    @Test func manualOverrideHiddenWithEmptyBacklog() {
        #expect(!CoachAutomation.showsManualOverride(llmInputs(hasBacklog: false)))
    }
}
