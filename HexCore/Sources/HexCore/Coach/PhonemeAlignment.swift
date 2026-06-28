import Foundation

// MARK: - Phoneme span

/// A phoneme aligned to an audio interval, with the acoustic model's average frame
/// log-probability for that phoneme over its frames — a Goodness-of-Pronunciation
/// (GOP) proxy: the closer to 0, the more confidently the audio matched the
/// expected phoneme; very negative = likely mispronounced.
public struct PhonemeSpan: Sendable, Equatable {
    /// Index into the acoustic model's phoneme vocabulary.
    public let label: Int
    /// Start offset in seconds from the beginning of the clip.
    public let start: Double
    /// End offset in seconds.
    public let end: Double
    /// Mean log-probability of `label` over the frames assigned to it (≤ 0).
    public let logProb: Double

    public init(label: Int, start: Double, end: Double, logProb: Double) {
        self.label = label
        self.start = start
        self.end = end
        self.logProb = logProb
    }
}

// MARK: - CTC forced alignment

/// On-device pronunciation substrate (deep-design: phoneme-grade timing). Given
/// per-frame phoneme log-probabilities from a CTC phoneme model **and** a known
/// target phoneme sequence, find the most likely monotonic alignment and return
/// each target phoneme's time interval + a GOP score.
///
/// Because the transcript is already known (from ASR), this *aligns* rather than
/// *recognizes* — far more accurate than free decoding. It's deliberately
/// model/runtime-agnostic: it consumes a plain emissions matrix, so the acoustic
/// model can run via Core ML or MLX without changing this code. Resolution is the
/// model's frame stride (≈20 ms for wav2vec2).
///
/// The algorithm is the standard CTC Viterbi forced-alignment over the
/// blank-interleaved target sequence `[∅, p0, ∅, p1, … , ∅]` (S = 2L+1 states),
/// with transitions: stay, advance one, or skip a blank between two *distinct*
/// phonemes.
public enum CTCForcedAligner {

    /// - Parameters:
    ///   - emissions: frame-major **log-probabilities**, `emissions[t][c]` for frame
    ///     `t` and phoneme class `c`. Convert raw logits with `logSoftmax(rows:)`.
    ///   - targets: expected phoneme label indices (in vocabulary space; no blanks).
    ///   - blank: the CTC blank class index.
    ///   - frameDuration: seconds per frame (e.g. `0.02`).
    /// - Returns: one span per target phoneme in order, or `nil` if alignment is
    ///   impossible (empty input, fewer frames than targets, or invalid labels).
    public static func align(
        emissions: [[Float]],
        targets: [Int],
        blank: Int,
        frameDuration: Double
    ) -> [PhonemeSpan]? {
        let frameCount = emissions.count
        let targetCount = targets.count
        guard frameCount > 0, targetCount > 0, frameCount >= targetCount else { return nil }
        let classCount = emissions[0].count
        guard classCount > 0, blank >= 0, blank < classCount else { return nil }
        guard targets.allSatisfy({ $0 >= 0 && $0 < classCount && $0 != blank }) else { return nil }

        let stateCount = 2 * targetCount + 1
        // Label emitted while in state `s`: even = blank, odd 2i+1 = targets[i].
        func label(of state: Int) -> Int { state % 2 == 0 ? blank : targets[(state - 1) / 2] }

        let negInf = -Float.greatestFiniteMagnitude / 4
        var score = Array(repeating: Array(repeating: negInf, count: stateCount), count: frameCount)
        var back = Array(repeating: Array(repeating: -1, count: stateCount), count: frameCount)

        // Frame 0: may start in the leading blank or the first phoneme.
        score[0][0] = emissions[0][blank]
        if stateCount > 1 { score[0][1] = emissions[0][targets[0]] }

        for t in 1 ..< frameCount {
            for s in 0 ..< stateCount {
                // Best predecessor: stay (s), advance (s-1), or skip the blank
                // between two distinct phonemes (s-2).
                var bestPrev = s
                var bestVal = score[t - 1][s]
                if s - 1 >= 0, score[t - 1][s - 1] > bestVal {
                    bestVal = score[t - 1][s - 1]; bestPrev = s - 1
                }
                if s - 2 >= 0, label(of: s) != blank, label(of: s - 2) != label(of: s),
                   score[t - 1][s - 2] > bestVal {
                    bestVal = score[t - 1][s - 2]; bestPrev = s - 2
                }
                if bestVal <= negInf { continue }
                score[t][s] = bestVal + emissions[t][label(of: s)]
                back[t][s] = bestPrev
            }
        }

        // Finish in the trailing blank or the last phoneme — whichever scores higher.
        var endState = stateCount - 1
        if stateCount - 2 >= 0, score[frameCount - 1][stateCount - 2] > score[frameCount - 1][endState] {
            endState = stateCount - 2
        }
        guard score[frameCount - 1][endState] > negInf else { return nil }

        // Backtrack to a per-frame state assignment.
        var statePath = Array(repeating: 0, count: frameCount)
        var s = endState
        for t in stride(from: frameCount - 1, through: 0, by: -1) {
            statePath[t] = s
            if t > 0 {
                s = back[t][s]
                if s < 0 { return nil }
            }
        }

        // Collapse contiguous frames in each phoneme (odd) state into spans.
        var spans: [PhonemeSpan] = []
        var i = 0
        while i < frameCount {
            let state = statePath[i]
            guard state % 2 == 1 else { i += 1; continue }
            let label = targets[(state - 1) / 2]
            var j = i
            var sum = 0.0
            while j < frameCount, statePath[j] == state {
                sum += Double(emissions[j][label])
                j += 1
            }
            let frames = j - i
            spans.append(PhonemeSpan(
                label: label,
                start: Double(i) * frameDuration,
                end: Double(j) * frameDuration,
                logProb: frames > 0 ? sum / Double(frames) : 0
            ))
            i = j
        }

        // Each target must align to exactly one span, in order.
        guard spans.count == targetCount else { return nil }
        return spans
    }

    /// Per-row (per-frame) log-softmax, to turn raw model logits into the
    /// log-probabilities `align` expects.
    public static func logSoftmax(rows: [[Float]]) -> [[Float]] {
        rows.map { row in
            guard let maxValue = row.max() else { return row }
            var sumExp: Float = 0
            for value in row { sumExp += Foundation.exp(value - maxValue) }
            let logSumExp = maxValue + Foundation.log(sumExp)
            return row.map { $0 - logSumExp }
        }
    }
}
