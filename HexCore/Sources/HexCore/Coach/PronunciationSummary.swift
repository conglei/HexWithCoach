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

/// One "sound to work on" for a note: an expected phoneme that came out weak,
/// what it most often turned into, how bad/often, and example words.
public struct PronunciationLesson: Sendable, Equatable, Identifiable {
    /// The expected IPA sound.
    public let expected: String
    /// The sound the speaker most often produced instead, when it consistently
    /// differed from `expected`. `nil` when the right sound was attempted but came
    /// out unclear (no dominant substitution) — then it's "unclear", not "you said X".
    public let actual: String?
    /// Mean GOP across this sound's weak instances (≤ 0, more negative = worse).
    public let meanGOP: Double
    /// How many weak instances of this sound occurred in the note.
    public let count: Int
    /// The learner's own words containing this weak sound (deduped, in order).
    public let exampleWords: [String]

    public var id: String { expected }

    public init(expected: String, actual: String?, meanGOP: Double, count: Int, exampleWords: [String]) {
        self.expected = expected
        self.actual = actual
        self.meanGOP = meanGOP
        self.count = count
        self.exampleWords = exampleWords
    }
}

public enum PronunciationSummary {
    /// The `maxLessons` sounds most worth working on in this note, worst/most-frequent
    /// first. Only *weak* phonemes (the `.weak` GOP bucket) count — the slightly-off
    /// and clear ones are intentionally omitted so the summary stays short.
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
            // Most common substitution; only call it a substitution if it happened
            // in at least half the weak instances (otherwise the sound was attempted
            // but just unclear). Ties broken toward the smaller symbol for determinism.
            let topSub = acc.substitutions.max { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
            }
            let actual = (topSub.map { Double($0.value) >= Double(acc.gops.count) / 2 } ?? false) ? topSub?.key : nil
            return PronunciationLesson(
                expected: expected,
                actual: actual,
                meanGOP: mean,
                count: acc.gops.count,
                exampleWords: Array(acc.words.prefix(exampleLimit))
            )
        }

        return Array(
            lessons.sorted {
                $0.count != $1.count ? $0.count > $1.count
                    : ($0.meanGOP != $1.meanGOP ? $0.meanGOP < $1.meanGOP : $0.expected < $1.expected)
            }
            .prefix(maxLessons)
        )
    }
}
