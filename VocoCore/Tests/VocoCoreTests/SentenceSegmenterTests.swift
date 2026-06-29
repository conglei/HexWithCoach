import Testing
@testable import VocoCore

/// Behavior spec for the paste-to-practice sentence segmenter (PR-3). Pasted text
/// becomes the ordered, speakable `segments` of a `PracticeItem`; these pin the
/// splitting, trimming, and edge cases the drill relies on.
@Suite struct SentenceSegmenterTests {

    @Test func splitsMultipleSentences() {
        let result = SentenceSegmenter.segments(
            from: "Hello there. How are you? I am fine!"
        )
        #expect(result == ["Hello there.", "How are you?", "I am fine!"])
    }

    @Test func trimsLeadingAndTrailingWhitespaceAndNewlines() {
        let result = SentenceSegmenter.segments(
            from: "\n  First sentence.   \n\n Second one.  \n"
        )
        #expect(result == ["First sentence.", "Second one."])
    }

    @Test func emptyInputYieldsEmptyArray() {
        #expect(SentenceSegmenter.segments(from: "").isEmpty)
    }

    @Test func whitespaceOnlyInputYieldsEmptyArray() {
        #expect(SentenceSegmenter.segments(from: "   \n\t  ").isEmpty)
    }

    @Test func singleSentenceWithoutTerminatorIsOneSegment() {
        let result = SentenceSegmenter.segments(from: "Just one line no period")
        #expect(result == ["Just one line no period"])
    }

    /// The NL tokenizer should not split on common abbreviations or decimals the
    /// way naive "." splitting would.
    @Test func handlesAbbreviationsGracefully() {
        let result = SentenceSegmenter.segments(
            from: "Dr. Smith paid $3.50. Then he left."
        )
        #expect(result.count == 2)
        #expect(result.first == "Dr. Smith paid $3.50.")
        #expect(result.last == "Then he left.")
    }

    /// Blank lines between paragraphs must not produce empty segments.
    @Test func dropsEmptySegmentsFromBlankLines() {
        let result = SentenceSegmenter.segments(
            from: "One.\n\n\nTwo."
        )
        #expect(result == ["One.", "Two."])
    }
}
