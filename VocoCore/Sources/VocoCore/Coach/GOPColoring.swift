import Foundation

// MARK: - GOP color bucketing (pure, deterministic)

/// Maps a Goodness-of-Pronunciation score to a small, deterministic set of
/// visual buckets for the layered note view (CI-9). GOP is `≤ 0`: closer to 0 =
/// the audio confidently matched the expected phoneme; very negative = likely
/// mispronounced. The note view paints each word/phoneme by its bucket — warmer
/// (worse) toward the bottom.
///
/// This is a *per-instance visual hint only* (ADR-0001): the buckets use fixed,
/// documented absolute cutoffs purely so the tint is stable and diffable across
/// renders. Pattern detection never consults these — it lives in
/// `PronunciationPatternDetector` and is strictly per-speaker-relative. Keep this
/// pure so the mapping is unit-testable without any UI.
public enum GOPColoring {
    /// A coarse pronunciation-confidence bucket. Ordered best → worst so callers
    /// can compare severity (`bucket.rawValue`); `neutral` sits last for the
    /// "no data" case so the plain transcript renders without a tint.
    public enum Bucket: Int, Sendable, Equatable, CaseIterable {
        /// Confidently native-like (GOP near 0).
        case good = 0
        /// Acceptable, minor deviation.
        case fair = 1
        /// Noticeably off — the warmest tint.
        case weak = 2
        /// No GOP available for this token; render neutral (untinted).
        case neutral = 3
    }

    /// GOP at or above this matched the expected phoneme confidently → `good`.
    /// First-pass, documented, tunable (design §8 open item 1). Mirrors the
    /// thresholds the shipped pronunciation sheet already used.
    public static let goodCutoff: Double = -0.3
    /// GOP at or above this is acceptable → `fair`; below it is `weak`.
    public static let fairCutoff: Double = -1.0

    /// Bucket a single GOP value. Pure. Higher (closer to 0) GOP is better.
    public static func bucket(forGOP gop: Double) -> Bucket {
        if gop >= goodCutoff { return .good }
        if gop >= fairCutoff { return .fair }
        return .weak
    }

    /// Bucket an optional GOP — `nil` (no measurement for this token) → `neutral`,
    /// so the layered view falls back to plain text gracefully.
    public static func bucket(forGOP gop: Double?) -> Bucket {
        guard let gop else { return .neutral }
        return bucket(forGOP: gop)
    }
}
