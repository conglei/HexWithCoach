import Foundation

/// Scores how closely a user's spoken repeat (RC-4 shadowing) matched the target
/// phrase. Word-level, case- and punctuation-insensitive — a light confirmation
/// that they produced the phrase, not a strict pronunciation grade (that's the
/// optional cloud check).
public enum ShadowingScorer {
    /// Default success threshold for `isMatch`.
    public static let matchThreshold = 0.7

    /// 0…1 similarity (1 = identical words).
    public static func match(target: String, spoken: String) -> Double {
        let a = tokenize(target)
        let b = tokenize(spoken)
        if a.isEmpty && b.isEmpty { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        let distance = wordEditDistance(a, b)
        let ratio = 1.0 - Double(distance) / Double(max(a.count, b.count))
        return min(1.0, max(0.0, ratio))
    }

    public static func isMatch(target: String, spoken: String, threshold: Double = matchThreshold) -> Bool {
        match(target: target, spoken: spoken) >= threshold
    }

    // MARK: - Internals

    private static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            // Drop apostrophes so contractions stay one token ("I'd" → "id").
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Levenshtein distance over word arrays.
    private static func wordEditDistance(_ a: [String], _ b: [String]) -> Int {
        var prev = Array(0 ... b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1 ... a.count {
            curr[0] = i
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
