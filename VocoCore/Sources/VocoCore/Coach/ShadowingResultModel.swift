//
//  ShadowingResultModel.swift
//  VocoCore
//
//  SR-2 — pure presentation logic for the shadowing *result* screen. Turns the two
//  independent signals an attempt produces — the ASR word match (were you
//  understood) and the per-phoneme GOP (how native-like the sounds were) — into a
//  small, honest model the SwiftUI view renders without any of its own thresholding:
//
//    • a dual-signal verdict (score + "right words" + "N sounds to polish"),
//    • a per-word quality tint (good / close / off) for the rendered phrase, and
//    • a focused, severity-ordered list of the top sound issues, each phrased with
//      `PhonemeAnchor` ("you said /oʊ/ (as in "robe") — aim for /ɑ/ (as in "rob")").
//
//  Pure and deterministic — no Core ML, no SwiftUI, no I/O — so the bucketing
//  thresholds and issue ordering are unit-testable in `swift test`.
//

import Foundation

public enum ShadowingResult {
    // MARK: - Per-word quality

    /// How native-like one word came out, from its mean per-phoneme GOP. Three
    /// buckets so the phrase can be tinted at a glance:
    ///   • `good`  — clearly native-like,
    ///   • `close` — understandable but a little off,
    ///   • `off`   — noticeably mispronounced (the underlined, tappable words).
    /// The cutoffs mirror `GOPColoring` / `ShadowingGOP.Quality` so the whole app
    /// reads pronunciation the same way (good ≥ -0.3, close ≥ -1.0, else off).
    public enum WordQuality: String, Sendable, Equatable, Codable, CaseIterable {
        case good, close, off

        /// Bucket a word's mean GOP. `good` ≥ `goodCutoff`, `close` ≥ `closeCutoff`,
        /// otherwise `off`. Pure; higher (nearer 0) GOP is better.
        public static func of(meanGOP: Double) -> WordQuality {
            if meanGOP >= goodCutoff { return .good }
            if meanGOP >= closeCutoff { return .close }
            return .off
        }
    }

    /// Mean GOP at or above this → a word reads as `good` (native-like). Same value
    /// `GOPColoring.goodCutoff` / `ShadowingGOP.goodThreshold` use per phoneme.
    public static let goodCutoff: Double = -0.3
    /// Mean GOP at or above this (but below `goodCutoff`) → `close`; below it → `off`.
    /// Same value as `GOPColoring.fairCutoff` / `ShadowingGOP.weakThreshold`.
    public static let closeCutoff: Double = -1.0

    /// One word of the target phrase, ready to render: the display text, its quality
    /// (when the GOP pipeline scored it), and the scored phonemes behind it (for the
    /// tap-to-expand detail). `quality == nil` means no GOP for this word — render it
    /// plain (out-of-dictionary, or no model). Only words with a non-nil `quality`
    /// that is `.off` are flagged (underlined + tappable).
    public struct Word: Sendable, Equatable, Identifiable {
        /// Stable index into the rendered phrase (also the identity).
        public let index: Int
        /// The word as it appears in the target phrase (original casing/punctuation).
        public let text: String
        /// Quality bucket, or `nil` when the word wasn't GOP-scored.
        public let quality: WordQuality?
        /// The word's scored phonemes (empty when not scored), for the detail view.
        public let phonemes: [PhonemeScore]

        public var id: Int { index }
        /// A flagged word: scored and clearly off — underlined and tappable.
        public var isFlagged: Bool { quality == .off }

        public init(index: Int, text: String, quality: WordQuality?, phonemes: [PhonemeScore]) {
            self.index = index
            self.text = text
            self.quality = quality
            self.phonemes = phonemes
        }
    }

    /// Split the target phrase into render tokens, pairing each with the analyzer's
    /// matching `WordScore` (when present) to derive its quality. The analyzer skips
    /// out-of-dictionary words, so we walk both sequences in order and match on the
    /// letters-only, lowercased word — robust to skipped tokens and punctuation.
    /// Words with no score get `quality == nil` (rendered plain).
    public static func words(target: String, result: PronunciationResult?) -> [Word] {
        let tokens = phraseTokens(target)
        guard let result else {
            return tokens.enumerated().map { Word(index: $0.offset, text: $0.element, quality: nil, phonemes: []) }
        }
        var scored = result.words
        var out: [Word] = []
        for (i, token) in tokens.enumerated() {
            let key = normalize(token)
            // Find the next analyzer word whose normalized text matches this token,
            // consuming it so repeated words pair left-to-right.
            if !key.isEmpty, let matchAt = scored.firstIndex(where: { normalize($0.word) == key }) {
                let ws = scored[matchAt]
                scored.removeSubrange(scored.startIndex ... matchAt) // drop it + any skipped-before
                let q = ws.phonemes.isEmpty ? nil : WordQuality.of(meanGOP: ws.gop)
                out.append(Word(index: i, text: token, quality: q, phonemes: ws.phonemes))
            } else {
                out.append(Word(index: i, text: token, quality: nil, phonemes: []))
            }
        }
        return out
    }

    /// Whitespace-split display tokens of the phrase, keeping punctuation attached so
    /// the rendered phrase looks natural. Empty tokens are dropped.
    static func phraseTokens(_ phrase: String) -> [String] {
        phrase.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
    }

    /// Letters + apostrophe, lowercased — the key both the phrase token and the
    /// analyzer word are reduced to so they pair regardless of casing/punctuation.
    static func normalize(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0 == "'" || $0 == "\u{2019}" }
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    // MARK: - Focused issues

    /// One sound issue to surface, already phrased for the learner. Built from a weak
    /// phoneme in a specific word: the `PhonemeAnchor` substitution text plus the
    /// articulation tip for the *aimed-for* sound. Ordered by severity upstream.
    public struct Issue: Sendable, Equatable, Identifiable {
        /// The word this issue occurred in (for "in "robe"").
        public let word: String
        /// Expected (aimed-for) IPA symbol.
        public let expected: String
        /// What the learner produced instead, when a dominant substitution exists.
        public let actual: String?
        /// Mean GOP for this sound's weak instances (more negative = worse).
        public let meanGOP: Double
        /// `PhonemeAnchor` substitution sentence, or a bare-IPA fallback for an
        /// unmapped symbol. e.g. `you said /oʊ/ (as in "robe") — aim for /ɑ/ (as in "rob")`.
        public let detail: String
        /// One-line articulation tip for the aimed-for sound, when `PhonemeAnchor`
        /// maps it; `nil` for an unmapped symbol (shouldn't happen — SR-1 is exhaustive).
        public let tip: String?

        public var id: String { "\(word)|\(expected)|\(actual ?? "")" }

        public init(word: String, expected: String, actual: String?, meanGOP: Double, detail: String, tip: String?) {
            self.word = word
            self.expected = expected
            self.actual = actual
            self.meanGOP = meanGOP
            self.detail = detail
            self.tip = tip
        }
    }

    /// The top `limit` sound issues for this attempt, most actionable/severe first.
    ///
    /// Severity ordering is delegated to `PronunciationSummary.lessons` (the same
    /// ranking the note summary uses: more-negative GOP first, concrete substitutions
    /// boosted, diffuse reduced vowels demoted and capped). Each surfaced lesson is
    /// then phrased with `PhonemeAnchor` and tied back to the word it occurred in.
    /// Returns `[]` when there's no GOP result or nothing came out weak.
    public static func issues(from result: PronunciationResult?, limit: Int = 3) -> [Issue] {
        guard let result else { return [] }
        let lessons = PronunciationSummary.lessons(from: result, maxLessons: limit)
        return lessons.map { lesson in
            let aim = lesson.expected
            // The sound actually produced: a dominant substitution, else the leading
            // observed production (the softer "sounded more like" case), else nil.
            let said = lesson.actual ?? lesson.leadingObserved
            let detail: String
            if let said {
                detail = PhonemeAnchor.substitutionText(said: said, aim: aim)
            } else {
                // No nameable substitution — frame it as an unclear aim.
                detail = "aim for " + annotated(aim)
            }
            return Issue(
                word: lesson.exampleWords.first ?? "",
                expected: aim,
                actual: said,
                meanGOP: lesson.meanGOP,
                detail: detail,
                tip: PhonemeAnchor.guide(for: aim)?.tip
            )
        }
    }

    /// `/sym/ (as in "word")` when `PhonemeAnchor` maps it, else just `/sym/`.
    private static func annotated(_ symbol: String) -> String {
        if let entry = PhonemeAnchor.guide(for: symbol) {
            return "/\(symbol)/ (as in \"\(entry.exemplar)\")"
        }
        return "/\(symbol)/"
    }

    // MARK: - Dual-signal verdict

    /// The honest, calibrated headline for the result. ASR match ("right words") and
    /// GOP issues ("N sounds to polish") are kept strictly separate so the screen
    /// never claims success while listing unresolved sound errors.
    public struct Verdict: Sendable, Equatable {
        /// ASR match score, 0…1 (mirrors `ShadowingModel.score`).
        public let score: Double
        /// Whether the learner produced the right words (`score ≥ ShadowingScorer.matchThreshold`).
        public let rightWords: Bool
        /// Number of distinct sound issues surfaced (the GOP signal). `nil` when there
        /// was no GOP result at all (no model / out-of-dictionary) — the UI then shows
        /// the ASR verdict alone and hides the sound signal.
        public let soundIssueCount: Int?
        /// The short, honest headline.
        public let headline: String
        /// A genuine win: right words AND (GOP ran with) zero sound issues.
        public let isWin: Bool

        public init(score: Double, rightWords: Bool, soundIssueCount: Int?, headline: String, isWin: Bool) {
            self.score = score
            self.rightWords = rightWords
            self.soundIssueCount = soundIssueCount
            self.headline = headline
            self.isWin = isWin
        }
    }

    /// Build the dual-signal verdict. `issueCount == nil` ⇒ no GOP available; the
    /// verdict then rests on the ASR match alone.
    ///
    /// Headlines, by case:
    ///   • right words + 0 issues (GOP ran) → a genuine win ("Nailed it!").
    ///   • right words + N issues          → "Almost there — N sound(s) to polish".
    ///   • right words + no GOP             → "Got the words" (sounds not measured).
    ///   • wrong words                       → "Let's try that again" (+ polish note).
    /// The verdict is a win ONLY in the first case — never while issues remain.
    public static func verdict(score: Double, issueCount: Int?, matchThreshold: Double = ShadowingScorer.matchThreshold) -> Verdict {
        let rightWords = score >= matchThreshold
        let isWin = rightWords && issueCount == 0
        let headline: String
        switch (rightWords, issueCount) {
        case (true, .some(0)):
            headline = "Nailed it!"
        case let (true, .some(n)):
            headline = "Almost there — \(n) sound\(n == 1 ? "" : "s") to polish"
        case (true, .none):
            headline = "Got the words"
        case let (false, .some(n)) where n > 0:
            headline = "Let's try that again — \(n) sound\(n == 1 ? "" : "s") to polish"
        default:
            headline = "Let's try that again"
        }
        return Verdict(score: score, rightWords: rightWords, soundIssueCount: issueCount, headline: headline, isWin: isWin)
    }
}
