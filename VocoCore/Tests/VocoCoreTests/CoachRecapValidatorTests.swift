import Foundation
import Testing
@testable import VocoCore

/// CF-fix — the deterministic gate that runs on the LLM recap before it's shown.
/// The load-bearing case (issue): a fabricated "flawless level 10" recap must be
/// REJECTED so the deterministic template is shown instead.
struct CoachRecapValidatorTests {

    private func input() -> CoachRecapInput {
        CoachRecapInput(
            lensTrends: [(.lexis, .needsWork), (.discourse, .improving)],
            findings: [
                CoachRecapInput.Finding(lens: .lexis, phrase: "overuses “basically”", trend: .needsWork, example: "basically just"),
            ],
            leadWinPhrase: "leaned on “um” and “uh”")
    }

    // MARK: Accept

    @Test
    func acceptsGroundedNumberFreeProse() {
        let text = "Your word choice is the clearest place to refine next; trimming filler words like “basically just” will make you land harder. Nice work clearing out the old habits."
        #expect(CoachRecapValidator.reject(text, input: input()) == nil)
    }

    @Test
    func acceptsAQuoteWeProvided() {
        // The example span we supplied may be quoted back verbatim.
        let text = "The one to polish is word choice — e.g. “basically just”."
        #expect(CoachRecapValidator.isValid(text, input: input()))
    }

    // MARK: Reject (a) numbers

    @Test
    func rejectsFabricatedLevelTen() {
        let text = "You're flawless — level 10 across the board."
        #expect(CoachRecapValidator.reject(text, input: input()) == .containsNumber)
    }

    @Test
    func rejectsAnyDigit() {
        let text = "That habit came up 9 times this week."
        #expect(CoachRecapValidator.reject(text, input: input()) == .containsNumber)
    }

    @Test
    func rejectsPerMinuteStat() {
        let text = "Your fillers are down to three per minute, nice."
        #expect(CoachRecapValidator.reject(text, input: input()) == .containsNumber)
    }

    @Test
    func rejectsSpelledOutCount() {
        let text = "You repeated that twice in the same breath."
        #expect(CoachRecapValidator.reject(text, input: input()) == .containsNumber)
    }

    @Test
    func rejectsTheWordLevelAsARating() {
        let text = "Your grammar is at an expert level here."
        #expect(CoachRecapValidator.reject(text, input: input()) == .containsNumber)
    }

    // MARK: Reject (b) ungrounded references

    @Test
    func rejectsAnUngroundedQuote() {
        // A quoted span we never supplied — the model invented an example.
        let text = "You said “the architecture is thorough” a lot lately."
        #expect(CoachRecapValidator.reject(text, input: input()) == .ungroundedReference)
    }

    @Test
    func rejectsAnUngroundedLensName() {
        // Pronunciation has no trend/finding in this input → naming it is ungrounded.
        let onlyLexis = CoachRecapInput(
            lensTrends: [(.lexis, .needsWork)],
            findings: [CoachRecapInput.Finding(lens: .lexis, phrase: "word choice", trend: .needsWork)],
            leadWinPhrase: nil)
        let text = "Your pronunciation is where to focus next."
        #expect(CoachRecapValidator.reject(text, input: onlyLexis) == .ungroundedReference)
    }

    // MARK: Reject (c) shape

    @Test
    func rejectsEmpty() {
        #expect(CoachRecapValidator.reject("   ", input: input()) == .empty)
    }

    @Test
    func rejectsMarkdownList() {
        let text = "Here is your recap:\n- Word choice\n- Clarity"
        #expect(CoachRecapValidator.reject(text, input: input()) == .notPlainProse)
    }

    @Test
    func rejectsTooManySentences() {
        // Six short, number-free sentences — over the 4-sentence cap.
        let clean = "Refine word choice. It matters. Keep going. You are close. Almost there. Push on."
        #expect(CoachRecapValidator.reject(clean, input: input()) == .badLength)
    }
}
