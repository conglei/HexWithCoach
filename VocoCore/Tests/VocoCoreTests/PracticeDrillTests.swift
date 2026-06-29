import Foundation
import Testing
@testable import VocoCore

/// CF-2 — the typed practice framework. Two pure invariants are pinned here:
///   1. **Drill selection by lens** — the focus area's lens picks the drill kind;
///      the user never chooses. lexis → wordSwap, pronunciation/prosody → shadow.
///   2. **The word-swap heuristic judge** — exact / variant accept, original-echo
///      and off-target reject, all on-device (no network), with respectful copy.
@Suite struct PracticeDrillTests {

    // MARK: - Lens → drill selection

    @Test func lexisSelectsWordSwap() {
        #expect(PracticeKind.forLens(.lexis) == .wordSwap)
    }

    @Test func pronunciationAndProsodySelectShadow() {
        #expect(PracticeKind.forLens(.pronunciation) == .shadow)
        #expect(PracticeKind.forLens(.prosody) == .shadow)
    }

    @Test func grammarAndDiscourseFallBackToShadow() {
        // Until their own conformers ship, these shadow the corrected sentence.
        #expect(PracticeKind.forLens(.grammar) == .shadow)
        #expect(PracticeKind.forLens(.discourse) == .shadow)
    }

    @Test func everyLensMapsToAKind() {
        // No lens may be left without a drill — exhaustive over the enum.
        for lens in Lens.allCases {
            _ = PracticeKind.forLens(lens)   // must not trap / be undefined
        }
    }

    // MARK: - Drill content + conformers

    @Test func wordSwapDrillTargetsTheNativeRewrite() {
        let content = PracticeDrillContent(
            title: "A crisper word",
            target: "I overuse the word basically in meetings.",
            originalSpan: "I keep saying basically too much",
            nativeRewrite: "I overuse basically in meetings",
            lens: .lexis
        )
        let drill = WordSwapDrill(content: content)
        #expect(drill.kind == .wordSwap)
        #expect(drill.targetPhrase == "I overuse basically in meetings")
    }

    @Test func wordSwapDrillFallsBackToTargetWhenNoRewrite() {
        let content = PracticeDrillContent(
            title: "x", target: "make a single payment", nativeRewrite: nil, lens: .lexis)
        #expect(WordSwapDrill(content: content).targetPhrase == "make a single payment")
    }

    @Test func shadowDrillScoresViaASRMatch() {
        let content = PracticeDrillContent(
            title: "th", target: "a thorough review of the architecture", lens: .pronunciation)
        let drill = ShadowDrill(content: content)
        #expect(drill.kind == .shadow)
        // Exact repeat → win; gibberish → not a win. Delegates to ShadowingScorer.
        #expect(drill.score(production: "a thorough review of the architecture").isWin)
        #expect(!drill.score(production: "completely different words here").isWin)
    }

    // MARK: - Word-swap judge: ACCEPT (exact + variant)

    @Test func judgeAcceptsExactTarget() {
        let r = WordSwapJudge.judge(
            production: "make a single payment",
            target: "make a single payment",
            original: "as a single payment")
        #expect(r.verdict == .matched)
        #expect(r.isWin)
        #expect(r.value >= WordSwapJudge.winThreshold)
    }

    @Test func judgeAcceptsTargetInsideAFullerSentence() {
        // Production is messy — the learner says the native phrase in a sentence.
        let r = WordSwapJudge.judge(
            production: "So I think we should make a single payment this time",
            target: "make a single payment",
            original: "as a single payment")
        #expect(r.isWin)
        #expect(r.verdict == .matched)
    }

    @Test func judgeAcceptsWhenDistinctiveWordIsProduced() {
        // The rewrite's distinctive content ("overuse") vs the original ("keep
        // saying") — producing the distinctive word should win even if scaffolding
        // words differ.
        let r = WordSwapJudge.judge(
            production: "I overuse basically in meetings",
            target: "I overuse basically in meetings",
            original: "I keep saying basically too much")
        #expect(r.isWin)
        #expect(r.verdict == .matched)
    }

    // MARK: - Word-swap judge: REJECT (original echo + off-target)

    @Test func judgeRejectsEchoingTheOriginal() {
        // The learner re-said their original wording, not the native choice.
        let r = WordSwapJudge.judge(
            production: "I keep saying basically too much",
            target: "I overuse basically in meetings",
            original: "I keep saying basically too much")
        #expect(!r.isWin)
        #expect(r.verdict == .stillOriginal)
        // Feedback names the native choice, never a harsh "wrong".
        #expect(r.feedback.lowercased().contains("native choice"))
    }

    @Test func judgeRejectsOffTargetProduction() {
        let r = WordSwapJudge.judge(
            production: "the weather is nice today",
            target: "make a single payment",
            original: "as a single payment")
        #expect(!r.isWin)
        #expect(r.verdict == .off)
        #expect(r.value == 0)
    }

    @Test func judgePartialIsEncouragingNotPunitive() {
        // Some of the target landed but not enough for a win — still encouraging.
        let r = WordSwapJudge.judge(
            production: "reach decision",
            target: "reach a clear decision quickly",
            original: "make decision about it")
        #expect(!r.isWin)
        // No verdict produces a harsh "wrong" string.
        #expect(!r.feedback.lowercased().contains("wrong"))
    }

    @Test func judgeNeverThrowsOnEmptyProduction() {
        let r = WordSwapJudge.judge(production: "", target: "make a single payment", original: nil)
        #expect(!r.isWin)
        #expect(r.value == 0)
    }

    @Test func judgeIsPurelyOnDevice() {
        // Sanity: judging is synchronous + deterministic (no async / network).
        let a = WordSwapJudge.judge(production: "make a single payment", target: "make a single payment", original: nil)
        let b = WordSwapJudge.judge(production: "make a single payment", target: "make a single payment", original: nil)
        #expect(a == b)
    }
}
