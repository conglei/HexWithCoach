import Foundation

/// The keyless L1 personalization prior (ADR-0003): given a learner's first
/// language, surface the English phonemes that learners with that L1 typically
/// struggle with, so keyless pronunciation coaching can prioritize them.
///
/// Pure and deterministic — it reads only the bundled ``TeachingContent``
/// (the L1→interference table + phoneme guide). L1 is asked once at onboarding
/// and stored outside HexCore; this helper turns that stored string into a
/// prioritized phoneme list. It is *not* wired into detection here.
public enum L1InterferencePrior {
    /// The interference phonemes (eSpeak-IPA) to prioritize for a learner's L1.
    ///
    /// Returns the L1's typical interference phonemes in table order, filtered to
    /// those that have a phoneme-guide entry (so a teaching card can be authored
    /// for each). Returns an empty array when the L1 is `nil`/blank or not in the
    /// bundled table — L1 is a booster, never a gate (ADR-0003).
    ///
    /// - Parameters:
    ///   - l1: The learner's first language key (case-insensitive), or `nil`.
    ///   - content: The bundled teaching content to read the prior from.
    /// - Returns: Prioritized IPA symbols, possibly empty. No duplicates.
    public static func prioritizedPhonemes(
        forL1 l1: String?,
        content: TeachingContent
    ) -> [String] {
        guard let l1, !l1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let entry = content.interference(forL1: l1)
        else { return [] }

        var seen = Set<String>()
        return entry.interferencePhonemes.filter { ipa in
            guard content.phoneme(ipa) != nil else { return false }
            return seen.insert(ipa).inserted
        }
    }
}
