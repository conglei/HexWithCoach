//
//  PronunciationSummary.swift
//  HexCore
//
//  Turns a note's raw per-phoneme GOP result into a short, human "what to work on"
//  summary instead of an overwhelming phoneme-by-phoneme dump. Groups the *weak*
//  phonemes by the expected sound, finds the substitution the speaker most often
//  made (from `PhonemeScore.actualSymbol`), and surfaces the learner's own example
//  words — so the UI can say "expected /ɛ/ → you said /ə/, in 'sense', 'tent'".
//
//  Pure and deterministic; no Core ML, no I/O.
//

import Foundation

/// One observed (actually-produced) sound for a weak phoneme, with how often the
/// recognizer heard it across the note's weak instances. Most-common first.
public struct ObservedSound: Sendable, Equatable {
    /// The IPA the recognizer actually heard (always differs from the expected sound).
    public let symbol: String
    /// How many of the expected sound's weak instances came out as this sound.
    public let count: Int

    public init(symbol: String, count: Int) {
        self.symbol = symbol
        self.count = count
    }
}

/// One "sound to work on" for a note: an expected phoneme that came out weak,
/// what it most often turned into, how bad/often, and example words.
public struct PronunciationLesson: Sendable, Equatable, Identifiable {
    /// The expected IPA sound.
    public let expected: String
    /// The sound the speaker most often produced instead, when it consistently
    /// differed from `expected`. `nil` when the right sound was attempted but came
    /// out unclear (no dominant substitution) — then it's "unclear", not "you said X".
    public let actual: String?
    /// Everything the recognizer actually heard for this sound's weak instances, most
    /// common first (excludes instances that hit the expected sound but scored weakly).
    /// Even when no single substitution dominated enough to set `actual`, this still
    /// tells the learner what their attempts *came out as* — e.g. "/ə/ … sounded more
    /// like /ɛ/". Empty when the model couldn't pin down any substitute.
    public let observed: [ObservedSound]
    /// Mean GOP across this sound's weak instances (≤ 0, more negative = worse).
    public let meanGOP: Double
    /// How many weak instances of this sound occurred in the note.
    public let count: Int
    /// The learner's own words containing this weak sound (deduped, in order).
    public let exampleWords: [String]

    public var id: String { expected }

    /// The single observed sound worth naming in the soft "unclear → sounded more like
    /// /X/" framing: the most common production when it didn't already dominate enough
    /// to be the `actual` substitution, and it still accounts for a meaningful share
    /// (≥ 30%) of the weak instances. `nil` when productions were too scattered to name
    /// one honestly — then the sound is just "unclear".
    public var leadingObserved: String? {
        guard actual == nil, let top = observed.first else { return nil }
        return Double(top.count) >= Double(count) * 0.3 ? top.symbol : nil
    }

    public init(
        expected: String,
        actual: String?,
        observed: [ObservedSound] = [],
        meanGOP: Double,
        count: Int,
        exampleWords: [String]
    ) {
        self.expected = expected
        self.actual = actual
        self.observed = observed
        self.meanGOP = meanGOP
        self.count = count
        self.exampleWords = exampleWords
    }
}

public enum PronunciationSummary {
    /// Reduced/centralized vowels that dominate connected speech. These show up
    /// constantly on long notes (schwa especially) but are the least teachable —
    /// they're a property of natural reduction, not a discrete error to drill. We
    /// demote them and cap them to at most one slot so they can't crowd out the
    /// genuinely fixable sounds.
    private static let reducedVowels: Set<String> = ["ə", "ɪ", "ʊ", "ɐ", "ᵻ"]

    /// The `maxLessons` sounds most worth working on in this note, most
    /// actionable/severe first. Only *weak* phonemes (the `.weak` GOP bucket) count —
    /// the slightly-off and clear ones are intentionally omitted so the summary stays short.
    public static func lessons(
        from result: PronunciationResult,
        maxLessons: Int = 3,
        exampleLimit: Int = 3
    ) -> [PronunciationLesson] {
        struct Accumulator {
            var gops: [Double] = []
            var substitutions: [String: Int] = [:]
            var words: [String] = []
            var seenWords = Set<String>()
        }

        var byExpected: [String: Accumulator] = [:]
        for word in result.words {
            for phoneme in word.phonemes {
                guard GOPColoring.bucket(forGOP: phoneme.gop) == .weak else { continue }
                var acc = byExpected[phoneme.symbol] ?? Accumulator()
                acc.gops.append(phoneme.gop)
                if let actual = phoneme.actualSymbol, actual != phoneme.symbol {
                    acc.substitutions[actual, default: 0] += 1
                }
                if acc.seenWords.insert(word.word).inserted {
                    acc.words.append(word.word)
                }
                byExpected[phoneme.symbol] = acc
            }
        }

        let lessons = byExpected.map { expected, acc -> PronunciationLesson in
            let mean = acc.gops.reduce(0, +) / Double(acc.gops.count)
            // The full distribution of what came out, most common first (ties broken
            // toward the smaller symbol for determinism).
            let observed = acc.substitutions
                .map { ObservedSound(symbol: $0.key, count: $0.value) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.symbol < $1.symbol }
            // Only call it a substitution ("you said /X/") if one sound dominated at
            // least half the weak instances; otherwise the sound was attempted but came
            // out unclear, and `observed` carries the softer "sounded more like" detail.
            let actual = (observed.first.map { Double($0.count) >= Double(acc.gops.count) / 2 } ?? false)
                ? observed.first?.symbol : nil
            return PronunciationLesson(
                expected: expected,
                actual: actual,
                observed: observed,
                meanGOP: mean,
                count: acc.gops.count,
                exampleWords: Array(acc.words.prefix(exampleLimit))
            )
        }

        // Rank by how actionable/severe each sound is, NOT by raw frequency: long notes
        // otherwise always surface the most common reduced sounds (schwa, /t/, /ɹ/),
        // which are the least teachable. A dominant substitution ("you said /X/") is more
        // actionable than a diffuse "unclear"; reduced vowels are demoted and capped to at
        // most one slot so they can't dominate the list.
        func severity(_ lesson: PronunciationLesson) -> Double {
            var score = -lesson.meanGOP // more-negative GOP ⇒ larger ⇒ more severe
            if lesson.actual != nil { score += 1.0 } // a concrete substitution is more actionable
            if Self.reducedVowels.contains(lesson.expected) { score -= 1.0 } // demote diffuse reduced sounds
            return score
        }

        let ranked = lessons.sorted {
            let a = severity($0), b = severity($1)
            if a != b { return a > b }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.expected < $1.expected
        }

        // Take the most severe sounds, but allow at most ONE reduced vowel in the result
        // so a single dominant schwa can't be followed by /ɪ/, /ʊ/, … crowding everything out.
        var result: [PronunciationLesson] = []
        var usedReducedVowel = false
        for lesson in ranked {
            if Self.reducedVowels.contains(lesson.expected) {
                if usedReducedVowel { continue }
                usedReducedVowel = true
            }
            result.append(lesson)
            if result.count >= maxLessons { break }
        }
        return result
    }
}
