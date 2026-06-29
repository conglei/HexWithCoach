import Foundation
import NaturalLanguage

/// Splits arbitrary pasted/typed text into speakable sentences for the shadowing
/// drill (PR-3 paste-to-practice). Pasted text is just a new *source* for the
/// existing `ShadowingModel`, so all this does is turn a blob into the ordered
/// `[String]` segments a `PracticeItem` stores and the drill iterates.
///
/// Pure and platform-agnostic (uses `NaturalLanguage`'s `NLTokenizer`), so it's
/// unit-testable under `swift test` without a simulator.
public enum SentenceSegmenter {
    /// Break `text` into trimmed, non-empty sentences in reading order.
    ///
    /// - Uses `NLTokenizer(unit: .sentence)`, so abbreviations ("Dr.", "U.S.")
    ///   and decimals are handled by the system tokenizer rather than naive
    ///   punctuation splitting.
    /// - Each returned sentence is whitespace/newline-trimmed; empties are dropped.
    /// - Empty or whitespace-only input yields `[]`.
    public static func segments(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex ..< trimmed.endIndex) { range, _ in
            let sentence = trimmed[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        return sentences
    }
}
