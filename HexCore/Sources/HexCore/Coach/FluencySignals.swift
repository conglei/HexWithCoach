import Foundation

// MARK: - Word timing

/// A single word with its start/end offsets (seconds) inside the utterance.
/// Supplied by the ASR when it exposes word-level timestamps. iOS on-device ASR
/// may not provide these yet — when absent, the text-based signals still carry
/// the V1 value and the pause stats are simply zeroed (see `FluencySignals`).
public struct WordTiming: Sendable, Equatable {
    public var word: String
    /// Start offset in seconds from the beginning of the utterance.
    public var start: Double
    /// End offset in seconds from the beginning of the utterance.
    public var end: Double

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}

// MARK: - Fluency signals

/// Objective, on-device prosody/fluency signals for a single utterance
/// (deep-design §4, pillar C: actually *hear* the speaker — real signals, not
/// LLM vibes). Computed deterministically from the ASR transcript (and, when
/// available, word timings) with NO LLM and NO network. Feeds the prosody/fluency
/// lens plus metrics/trends (RC-6).
///
/// All fields are raw/precise; the `metrics` dictionary rounds them for trend
/// storage. Pause fields are zero unless word timings were provided.
public struct FluencySignals: Codable, Sendable, Equatable {
    // Pace
    /// Words per minute. Zero when `durationSec <= 0`.
    public var wordsPerMinute: Double
    /// Total whitespace-tokenized words.
    public var wordCount: Int
    /// Utterance duration in seconds (as measured by the recorder).
    public var durationSec: Double

    // Fillers
    /// Filler tokens/phrases per minute. Zero when `durationSec <= 0`.
    public var fillersPerMinute: Double
    /// Count of filler tokens/phrases (um/uh/like/you know/…).
    public var fillerCount: Int

    // Restarts / false starts
    /// Count of immediate repeats ("the the") + dash self-corrections ("I want— I need").
    public var restartCount: Int

    // Pause stats — only meaningful when word timings were supplied; zero otherwise.
    /// Number of inter-word gaps longer than `pauseThresholdSec` (~0.3s).
    public var pauseCount: Int
    /// Mean duration (seconds) of the gaps counted in `pauseCount`. Zero when none.
    public var meanPauseSec: Double
    /// Fraction (0…1) of *all* inter-word gaps longer than `longPauseThresholdSec` (~1.0s).
    public var longPauseRate: Double
    /// Whether pause stats were actually computed (word timings present). When
    /// false, the three pause fields are zero placeholders, not measurements.
    public var hasPauseStats: Bool

    public init(
        wordsPerMinute: Double = 0,
        wordCount: Int = 0,
        durationSec: Double = 0,
        fillersPerMinute: Double = 0,
        fillerCount: Int = 0,
        restartCount: Int = 0,
        pauseCount: Int = 0,
        meanPauseSec: Double = 0,
        longPauseRate: Double = 0,
        hasPauseStats: Bool = false
    ) {
        self.wordsPerMinute = wordsPerMinute
        self.wordCount = wordCount
        self.durationSec = durationSec
        self.fillersPerMinute = fillersPerMinute
        self.fillerCount = fillerCount
        self.restartCount = restartCount
        self.pauseCount = pauseCount
        self.meanPauseSec = meanPauseSec
        self.longPauseRate = longPauseRate
        self.hasPauseStats = hasPauseStats
    }

    /// Structured signals for trends/RC-6. Rates and seconds are rounded to 1–2
    /// decimals (the raw fields stay precise). Pause keys are included only when
    /// `hasPauseStats` is true, so trend charts never plot placeholder zeros.
    public var metrics: [String: Double] {
        var m: [String: Double] = [
            "wordsPerMinute": Self.round1(wordsPerMinute),
            "fillersPerMinute": Self.round2(fillersPerMinute),
            "fillerCount": Double(fillerCount),
            "restartCount": Double(restartCount),
            "wordCount": Double(wordCount),
            "durationSec": Self.round1(durationSec),
        ]
        if hasPauseStats {
            m["pauseCount"] = Double(pauseCount)
            m["meanPauseSec"] = Self.round2(meanPauseSec)
            m["longPauseRate"] = Self.round2(longPauseRate)
        }
        return m
    }

    private static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
    private static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}

// MARK: - Analyzer

/// Pure, deterministic computation of `FluencySignals` from an ASR transcript and
/// optional word timings. No LLM, no network — everything here is local + free
/// (deep-design §4). Stateless: exposed as static functions.
public enum FluencyAnalyzer {
    /// Single-token fillers, matched case-insensitively on word boundaries.
    /// "like" is included as a discourse-filler ("it's, like, hard").
    public static let defaultSingleWordFillers: Set<String> = [
        "um", "uh", "uhh", "umm", "er", "ah", "mm", "like",
    ]

    /// Multi-word filler phrases, matched case-insensitively on word boundaries.
    public static let defaultMultiWordFillers: [String] = [
        "you know", "i mean", "sort of", "kind of", "i guess",
    ]

    /// Gaps longer than this (seconds) count as a pause.
    public static let pauseThresholdSec: Double = 0.3
    /// Gaps longer than this (seconds) count as a *long* pause.
    public static let longPauseThresholdSec: Double = 1.0

    /// Compute objective fluency signals.
    ///
    /// - Parameters:
    ///   - transcript: the recognized text (used for word/filler/restart counts).
    ///   - durationSec: measured utterance length; `<= 0` yields zero rates and
    ///     never divides by zero.
    ///   - wordTimings: optional word-level timestamps; when non-nil, pause stats
    ///     are computed from inter-word gaps. When nil, pause fields stay zero and
    ///     `hasPauseStats` is false.
    public static func analyze(
        transcript: String,
        durationSec: Double,
        wordTimings: [WordTiming]? = nil
    ) -> FluencySignals {
        let tokens = tokenize(transcript)
        let wordCount = tokens.count

        let minutes = durationSec > 0 ? durationSec / 60.0 : 0
        let wpm = minutes > 0 ? Double(wordCount) / minutes : 0

        let fillerCount = countFillers(in: tokens, rawTranscript: transcript)
        let fpm = minutes > 0 ? Double(fillerCount) / minutes : 0

        let restartCount = countRestarts(tokens: tokens, rawTranscript: transcript)

        var signals = FluencySignals(
            wordsPerMinute: wpm,
            wordCount: wordCount,
            durationSec: max(0, durationSec),
            fillersPerMinute: fpm,
            fillerCount: fillerCount,
            restartCount: restartCount
        )

        if let timings = wordTimings, timings.count >= 2 {
            let pause = pauseStats(for: timings)
            signals.pauseCount = pause.count
            signals.meanPauseSec = pause.mean
            signals.longPauseRate = pause.longRate
            signals.hasPauseStats = true
        }

        return signals
    }

    // MARK: Tokenization

    /// Lowercased word tokens, stripped of surrounding punctuation. Whitespace
    /// tokenization per spec; we additionally trim edge punctuation so "um," and
    /// "like." match the filler set, while keeping intra-word characters intact.
    static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    // MARK: Fillers

    private static func countFillers(in tokens: [String], rawTranscript: String) -> Int {
        // Single-word fillers: exact token match (already lowercased + de-punctuated).
        var count = tokens.reduce(0) { $0 + (defaultSingleWordFillers.contains($1) ? 1 : 0) }

        // Multi-word fillers: scan the token stream for consecutive matches so we
        // get word-boundary matching for free (no substring false positives like
        // "kind of" inside "mankind off").
        for phrase in defaultMultiWordFillers {
            let needle = phrase.split(separator: " ").map(String.init)
            count += consecutiveMatches(of: needle, in: tokens)
        }
        return count
    }

    /// Number of non-overlapping occurrences of `needle` as a consecutive run in `haystack`.
    private static func consecutiveMatches(of needle: [String], in haystack: [String]) -> Int {
        guard !needle.isEmpty, haystack.count >= needle.count else { return 0 }
        var count = 0
        var i = 0
        while i <= haystack.count - needle.count {
            if Array(haystack[i ..< i + needle.count]) == needle {
                count += 1
                i += needle.count // non-overlapping
            } else {
                i += 1
            }
        }
        return count
    }

    // MARK: Restarts / false starts

    /// Simple, documented heuristic for restarts / false starts:
    ///   1. Immediate repeated identical words ("the the", "I I") in the token stream.
    ///   2. Dash / em-dash self-corrections ("I want— I need"): a hyphen or em-dash
    ///      that abuts a word and is followed by more speech.
    /// Deliberately conservative — it under-counts rather than inventing restarts.
    private static func countRestarts(tokens: [String], rawTranscript: String) -> Int {
        var count = 0

        // 1. Adjacent identical tokens.
        if tokens.count >= 2 {
            for i in 1 ..< tokens.count where tokens[i] == tokens[i - 1] {
                count += 1
            }
        }

        // 2. Dash self-corrections: a hyphen-minus or em/en-dash adjacent to a
        // word character, with non-whitespace text remaining after it.
        let dashScalars: Set<Character> = ["-", "\u{2014}", "\u{2013}"] // - — –
        let chars = Array(rawTranscript)
        for (i, ch) in chars.enumerated() where dashScalars.contains(ch) {
            let prevIsWord = i > 0 && chars[i - 1].isLetter
            // Something meaningful follows the dash (possibly after a space).
            let restHasWord = chars[(i + 1)...].contains { $0.isLetter }
            if prevIsWord && restHasWord {
                count += 1
            }
        }

        return count
    }

    // MARK: Pause stats

    private static func pauseStats(for timings: [WordTiming]) -> (count: Int, mean: Double, longRate: Double) {
        // Inter-word gaps: previous word's end → next word's start. Clamp negatives
        // (overlapping/identical timestamps) to zero.
        var gaps: [Double] = []
        gaps.reserveCapacity(timings.count - 1)
        for i in 1 ..< timings.count {
            gaps.append(max(0, timings[i].start - timings[i - 1].end))
        }
        guard !gaps.isEmpty else { return (0, 0, 0) }

        let pauses = gaps.filter { $0 > pauseThresholdSec }
        let mean = pauses.isEmpty ? 0 : pauses.reduce(0, +) / Double(pauses.count)
        let longCount = gaps.filter { $0 > longPauseThresholdSec }.count
        let longRate = Double(longCount) / Double(gaps.count)
        return (pauses.count, mean, longRate)
    }
}
