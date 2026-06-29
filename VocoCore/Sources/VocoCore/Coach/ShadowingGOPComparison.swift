import Foundation

/// CI-11 — closed-loop shadowing. After the learner records their shadow attempt,
/// we run the same on-device pronunciation pipeline (#57) on the attempt audio
/// against the practiced phrase, producing per-phoneme GOPs. This pure helper
/// *compares* those attempt GOPs against a target reference and emits a per-phoneme
/// verdict + delta — e.g. /θ/ went red→green — so the result screen can show real
/// segmental improvement on top of the existing ASR pass/fail.
///
/// It is deliberately model-free: it consumes two already-scored
/// `PronunciationResult`s and is fully unit-testable with synthetic GOP.
public enum ShadowingGOP {
    /// GOP cutoffs (≤ 0; closer to 0 = better). Mirror the per-instance color hint
    /// thresholds used in the pronunciation sheet so the closed loop reads the same
    /// way: ≥ -0.3 "good", ≥ -1.0 "okay", below that "weak".
    public static let goodThreshold = -0.3
    public static let weakThreshold = -1.0

    /// A coarse, learner-facing quality band for a single phoneme's GOP.
    public enum Quality: String, Sendable, Equatable, Codable {
        case good, okay, weak

        public static func of(gop: Double) -> Quality {
            if gop >= goodThreshold { return .good }
            if gop >= weakThreshold { return .okay }
            return .weak
        }
    }

    /// How the attempt compares to the target reference for one phoneme.
    public enum Verdict: String, Sendable, Equatable, Codable {
        /// Crossed up into a better band (e.g. weak/okay → good) — the headline win.
        case improved
        /// Same band, but a clearly better GOP within it.
        case better
        /// Roughly unchanged.
        case same
        /// Clearly worse (lower band, or a meaningful drop).
        case worse
    }

    /// One phoneme's before/after comparison.
    public struct PhonemeDelta: Sendable, Equatable, Codable {
        public let symbol: String
        public let targetGOP: Double
        public let attemptGOP: Double
        public let targetQuality: Quality
        public let attemptQuality: Quality
        public let verdict: Verdict
        /// attemptGOP − targetGOP (positive = the attempt scored closer to native).
        public var delta: Double { attemptGOP - targetGOP }

        public init(symbol: String, targetGOP: Double, attemptGOP: Double) {
            self.symbol = symbol
            self.targetGOP = targetGOP
            self.attemptGOP = attemptGOP
            self.targetQuality = Quality.of(gop: targetGOP)
            self.attemptQuality = Quality.of(gop: attemptGOP)
            self.verdict = Self.verdict(target: targetGOP, attempt: attemptGOP)
        }

        /// GOP difference below which we treat the two as "same" (avoids noise from
        /// per-instance jitter being read as progress).
        static let noticeableDelta = 0.25

        static func verdict(target: Double, attempt: Double) -> Verdict {
            let tq = Quality.of(gop: target)
            let aq = Quality.of(gop: attempt)
            let d = attempt - target
            if aq.rank > tq.rank, d >= noticeableDelta { return .improved }
            if aq.rank < tq.rank, d <= -noticeableDelta { return .worse }
            if d >= noticeableDelta { return .better }
            if d <= -noticeableDelta { return .worse }
            return .same
        }
    }

    /// The full per-phoneme comparison for a shadow attempt.
    public struct Comparison: Sendable, Equatable, Codable {
        public let phonemes: [PhonemeDelta]
        public init(phonemes: [PhonemeDelta]) { self.phonemes = phonemes }

        public var isEmpty: Bool { phonemes.isEmpty }
        /// Phonemes that crossed up into a better band — the deltas worth surfacing
        /// as the headline ("/θ/ red → green").
        public var improved: [PhonemeDelta] { phonemes.filter { $0.verdict == .improved } }
        /// Phonemes that got clearly worse — gentle "watch this one" hints.
        public var regressed: [PhonemeDelta] { phonemes.filter { $0.verdict == .worse } }
        /// Phonemes still in the weak band on the attempt — what's left to work on.
        public var stillWeak: [PhonemeDelta] { phonemes.filter { $0.attemptQuality == .weak } }
    }

    /// Compare an attempt's per-phoneme GOPs against a target reference's. Both are
    /// the analyzer's output for the *same* practiced phrase. Phonemes are paired by
    /// walking both flattened sequences in order and matching on symbol — robust to
    /// the analyzer skipping an out-of-dictionary word in one pass but not the other.
    public static func compare(target: PronunciationResult, attempt: PronunciationResult) -> Comparison {
        let t = target.words.flatMap(\.phonemes)
        let a = attempt.words.flatMap(\.phonemes)
        var deltas: [PhonemeDelta] = []
        var i = 0, j = 0
        while i < t.count, j < a.count {
            if t[i].symbol == a[j].symbol {
                deltas.append(PhonemeDelta(symbol: t[i].symbol, targetGOP: t[i].gop, attemptGOP: a[j].gop))
                i += 1; j += 1
            } else if let nextJ = nextMatch(of: t[i].symbol, in: a, from: j + 1), nextJ - j <= 2 {
                // The attempt inserted an extra phoneme — skip ahead to realign.
                j = nextJ
            } else {
                // The target phoneme is missing from (or shifted in) the attempt — skip it.
                i += 1
            }
        }
        return Comparison(phonemes: deltas)
    }

    private static func nextMatch(of symbol: String, in seq: [PhonemeScore], from: Int) -> Int? {
        var k = from
        while k < seq.count {
            if seq[k].symbol == symbol { return k }
            k += 1
        }
        return nil
    }
}

private extension ShadowingGOP.Quality {
    /// good > okay > weak, for band comparisons.
    var rank: Int {
        switch self {
        case .weak: return 0
        case .okay: return 1
        case .good: return 2
        }
    }
}
