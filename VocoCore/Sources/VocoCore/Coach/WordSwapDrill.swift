//
//  WordSwapDrill.swift
//  VocoCore
//
//  CF-2 — the `wordSwap` drill: the vocabulary / naturalness drill. For a fluent
//  speaker, the highest-value polish is word choice: "you said X; a native would
//  reach for Y." Shadowing the corrected sentence would only rehearse the *sounds*;
//  the learning here is the *decision*, so the drill makes the user **produce** the
//  more-natural word/phrase rather than read it.
//
//  Flow (the view drives it): a quick recognition warm-up (see the before/after),
//  then production — the user says the better phrasing aloud and we judge whether
//  they produced the target span (`nativeRewrite`) or an acceptable variant.
//
//  Judging is a pure on-device heuristic (`WordSwapJudge`) so it **degrades
//  gracefully with no API key** — practice never blocks on the network. An optional
//  LLM judge can layer on later in the paid lane; the heuristic is the floor.
//

import Foundation

// MARK: - Shadow drill (the existing pronunciation drill, as a conformer)

/// The existing shadowing loop ("hear → say → GOP"), expressed as a `PracticeDrill`
/// so it's one member of the typed family rather than the only thing practice can
/// do. Scoring delegates to `ShadowingScorer` (the same ASR word-match the
/// `ShadowingModel` uses), so there is **no behavior change** — `ShadowingView` /
/// `ShadowingModel` still own the live TTS/ASR/GOP; this just names shadowing as a
/// drill kind and gives the framework a uniform `score(production:)`.
public struct ShadowDrill: PracticeDrill {
    public let content: PracticeDrillContent
    public var kind: PracticeKind { .shadow }

    public init(content: PracticeDrillContent) {
        self.content = content
    }

    /// Word-match of the spoken repeat against the target — identical to the
    /// shadowing result's ASR signal. (The richer per-phoneme GOP still lives in
    /// `ShadowingModel`; this is the framework-level summary score.)
    public func score(production: String) -> DrillScore {
        let value = ShadowingScorer.match(target: content.target, spoken: production)
        let win = value >= ShadowingScorer.matchThreshold
        return DrillScore(
            value: value,
            isWin: win,
            feedback: win ? "Nicely said." : "Close — give it another go."
        )
    }
}

// MARK: - Word-swap drill

/// The vocabulary drill. `content.originalSpan` is what the learner said;
/// `content.nativeRewrite` is the more-natural target they must produce.
public struct WordSwapDrill: PracticeDrill {
    public let content: PracticeDrillContent
    public var kind: PracticeKind { .wordSwap }

    public init(content: PracticeDrillContent) {
        self.content = content
    }

    /// The phrase the learner is being nudged toward. Prefer the explicit
    /// `nativeRewrite`; fall back to the target sentence so a card with only a
    /// rewritten sentence still yields a usable target.
    public var targetPhrase: String {
        let rewrite = content.nativeRewrite?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rewrite.isEmpty { return rewrite }
        return content.target
    }

    /// Judge what the learner produced against the target phrase, on-device.
    public func score(production: String) -> DrillScore {
        let result = WordSwapJudge.judge(
            production: production,
            target: targetPhrase,
            original: content.originalSpan
        )
        return DrillScore(value: result.value, isWin: result.isWin, feedback: result.feedback)
    }
}

// MARK: - Heuristic judge

/// Pure, on-device judge for the `wordSwap` drill — "did the learner produce the
/// native choice (or an acceptable variant)?" — with respectful, never-punitive
/// feedback. This is the reliability floor: it works with **no API key and no
/// network**. An optional LLM judge can refine it later; this never blocks.
///
/// The judge looks for the *content* of the target rather than an exact match,
/// because production is messy (the learner may say a fuller sentence around the
/// target word). The signal that matters is: did the key lexical content of the
/// native rewrite show up, and did they move *off* the original wording?
public enum WordSwapJudge {
    /// The judge's verdict bands, so the UI can phrase encouragement honestly.
    public enum Verdict: Sendable, Equatable {
        case matched       // produced the native choice (or a clear variant)
        case partial       // some of it landed — encourage, don't fail harshly
        case stillOriginal // produced (essentially) the original wording again
        case off           // didn't produce the target content
    }

    /// Outcome of judging a production.
    public struct Result: Sendable, Equatable {
        public var verdict: Verdict
        /// 0…1 coverage of the target's key content words.
        public var value: Double
        public var isWin: Bool
        public var feedback: String
    }

    /// "Good enough" bar for a win: the production must cover most of the target's
    /// key content words. Tuned so a learner who says the native phrase inside a
    /// fuller sentence still wins, while one who only echoes the original doesn't.
    public static let winThreshold = 0.75

    /// Judge `production` against the `target` (the native rewrite), optionally
    /// using the `original` span to detect "you just said the same thing again".
    public static func judge(production: String, target: String, original: String?) -> Result {
        let targetKeys = keyContentWords(target)
        let producedAll = contentWords(production)
        let producedSet = Set(producedAll)

        // Degenerate target (no content words): fall back to a light word match so
        // the drill never hard-fails on thin content.
        guard !targetKeys.isEmpty else {
            let m = ShadowingScorer.match(target: target, spoken: production)
            return Result(
                verdict: m >= winThreshold ? .matched : .partial,
                value: m, isWin: m >= winThreshold,
                feedback: m >= winThreshold ? "That works." : "Give it another try."
            )
        }

        // Coverage = fraction of the target's *distinctive* content words the
        // learner actually produced. Distinctive = present in the rewrite but not
        // in the original (the words that make the rewrite the better choice),
        // falling back to all target content words when nothing is distinctive.
        let originalSet = Set(contentWords(original ?? ""))
        let distinctive = targetKeys.filter { !originalSet.contains($0) }
        let scoringKeys = distinctive.isEmpty ? targetKeys : distinctive
        let hit = scoringKeys.filter { producedSet.contains($0) }.count
        let coverage = Double(hit) / Double(scoringKeys.count)

        // Did they essentially re-say the original wording? Only relevant when the
        // original carries content words the rewrite dropped.
        let originalOnly = originalSet.subtracting(Set(targetKeys))
        let echoedOriginal = !originalOnly.isEmpty
            && originalOnly.allSatisfy(producedSet.contains)
            && coverage < winThreshold

        let nativeWord = scoringKeys.first ?? targetKeys.first ?? target

        if coverage >= winThreshold {
            return Result(
                verdict: .matched, value: coverage, isWin: true,
                feedback: "That's the native choice — nicely done."
            )
        } else if echoedOriginal {
            return Result(
                verdict: .stillOriginal, value: coverage, isWin: false,
                feedback: "Closer to your original — the native choice here is “\(nativeWord)”."
            )
        } else if coverage > 0 {
            return Result(
                verdict: .partial, value: coverage, isWin: false,
                feedback: "Almost — reach for “\(nativeWord)”."
            )
        } else {
            return Result(
                verdict: .off, value: 0, isWin: false,
                feedback: "The native choice here is “\(nativeWord)”. Try saying it that way."
            )
        }
    }

    // MARK: - Tokenization

    /// Lowercased alphanumeric tokens, apostrophes folded (mirrors `ShadowingScorer`
    /// so the two judges agree on what a "word" is).
    static func contentWords(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .filter { !stopWords.contains($0) }
    }

    /// Deduped content words, preserving first-seen order — the "keys" a production
    /// must cover. Stop words are dropped so coverage rewards the lexical content
    /// (the actual word choice) rather than the scaffolding around it.
    static func keyContentWords(_ s: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for w in contentWords(s) where !seen.contains(w) {
            seen.insert(w)
            out.append(w)
        }
        return out
    }

    /// Function words that carry no lexical "choice" signal — excluded from
    /// coverage so judging tracks the words that make a phrasing more natural.
    static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "at",
        "for", "with", "as", "by", "is", "are", "was", "were", "be", "been",
        "it", "its", "i", "you", "he", "she", "we", "they", "them", "this",
        "that", "these", "those", "my", "your", "our", "their", "do", "does",
        "did", "so", "if", "then", "than", "too", "very", "just", "up", "out",
    ]
}
