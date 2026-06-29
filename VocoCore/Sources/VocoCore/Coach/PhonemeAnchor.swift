import Foundation

/// Turns a raw IPA phoneme into something a learner can act on: an **exemplar word**
/// that obviously contains the sound and a one-line **articulation tip**. Bare IPA
/// tells an advanced learner what's wrong; the anchor + tip tells *everyone* how to fix
/// it (e.g. "/ɑ/ as in *rob* — drop your jaw, keep it short").
///
/// Pure value type — no UIKit/SwiftUI. The symbol set covers exactly the inventory the
/// GOP pipeline can emit (`PhonemeG2P.producibleSymbols`); see `PhonemeAnchorTests`,
/// which fails if any producible symbol is left unmapped so coverage can't silently rot.
///
/// Note: named `PhonemeAnchor` (not `PhonemeGuide`) because `PhonemeGuide` already names
/// the richer JSON-backed teaching asset in `TeachingContent.swift`. That asset's
/// inventory is *not* aligned to the GOP pipeline's producible symbols (it has long-vowel
/// variants like `ɑː`/`ɔː`/`ɜː` the G2P never emits, and lacks the bare `ɑ`/`ɔ` it does),
/// so it can't guarantee no-unmapped-symbol coverage. This lightweight lookup does, and
/// is what SR-2's result screen renders for substitution feedback.
public enum PhonemeAnchor {
    /// A learner-facing anchor for one phoneme.
    public struct Entry: Equatable, Sendable {
        /// A common word that obviously contains the sound, e.g. "rob" for /ɑ/.
        public let exemplar: String
        /// How to make the sound, ≤ ~12 words.
        public let tip: String
        public init(exemplar: String, tip: String) {
            self.exemplar = exemplar
            self.tip = tip
        }
    }

    /// The anchor for `phoneme`, or `nil` for an unknown symbol so callers can fall back
    /// to bare IPA and never crash.
    public static func guide(for phoneme: String) -> Entry? { entries[phoneme] }

    /// Phrase a substitution for feedback, e.g.
    /// `you said /oʊ/ (as in "robe") — aim for /ɑ/ (as in "rob")`.
    /// Falls back to bare IPA for any symbol that isn't mapped.
    public static func substitutionText(said: String, aim: String) -> String {
        "you said \(annotated(said)) — aim for \(annotated(aim))"
    }

    /// `/sym/ (as in "word")` when mapped, otherwise just `/sym/`.
    private static func annotated(_ symbol: String) -> String {
        if let entry = entries[symbol] {
            return "/\(symbol)/ (as in \"\(entry.exemplar)\")"
        }
        return "/\(symbol)/"
    }

    /// IPA → anchor. Keys are exactly `PhonemeG2P.producibleSymbols` (eSpeak-IPA as the
    /// model emits them, plus the `ə` schwa). Keep in sync with that inventory.
    private static let entries: [String: Entry] = [
        // Vowels
        "ɑ":  Entry(exemplar: "rob",    tip: "Drop your jaw, open mouth, keep it short."),
        "æ":  Entry(exemplar: "cat",    tip: "Wide flat mouth, tongue low and forward."),
        "ʌ":  Entry(exemplar: "cup",    tip: "Relaxed central vowel, mouth half open."),
        "ɔ":  Entry(exemplar: "thought",tip: "Round your lips, tongue low and back."),
        "ɛ":  Entry(exemplar: "bed",    tip: "Tongue mid-front, mouth slightly open."),
        "ɪ":  Entry(exemplar: "sit",    tip: "Short, relaxed; don't tense into \"ee\"."),
        "iː": Entry(exemplar: "see",    tip: "Long tense \"ee\"; smile, tongue high front."),
        "ʊ":  Entry(exemplar: "book",   tip: "Short, lips loosely rounded, tongue back."),
        "uː": Entry(exemplar: "blue",   tip: "Long \"oo\"; round lips tightly, tongue back."),
        "ə":  Entry(exemplar: "about",  tip: "Quick, weak, unstressed; relax the mouth."),
        "ɚ":  Entry(exemplar: "butter", tip: "Schwa with the tongue curled for an R."),
        // Diphthongs
        "aʊ": Entry(exemplar: "now",    tip: "Glide from \"ah\" to \"oo\", rounding lips."),
        "aɪ": Entry(exemplar: "price",  tip: "Glide from \"ah\" up to \"ee\"."),
        "eɪ": Entry(exemplar: "gray",   tip: "Glide from \"eh\" up to \"ee\"."),
        "oʊ": Entry(exemplar: "robe",   tip: "Glide from \"oh\" to \"oo\", rounding lips."),
        "ɔɪ": Entry(exemplar: "boy",    tip: "Glide from \"aw\" up to \"ee\"."),
        // Consonants
        "b":  Entry(exemplar: "bee",    tip: "Press lips together, then voice the burst."),
        "tʃ": Entry(exemplar: "church", tip: "Quick \"t\" then \"sh\"; no voice."),
        "d":  Entry(exemplar: "dog",    tip: "Tongue taps behind teeth, with voice."),
        "ð":  Entry(exemplar: "this",   tip: "Tongue between teeth, soft and voiced."),
        "f":  Entry(exemplar: "fan",    tip: "Top teeth on lower lip, blow air."),
        "ɡ":  Entry(exemplar: "go",     tip: "Back of tongue taps the soft palate, voiced."),
        "h":  Entry(exemplar: "hat",    tip: "Just a quiet breath of air out."),
        "dʒ": Entry(exemplar: "judge",  tip: "Quick \"d\" then \"zh\", with voice."),
        "k":  Entry(exemplar: "key",    tip: "Back of tongue taps soft palate, no voice."),
        "l":  Entry(exemplar: "love",   tip: "Tongue tip behind teeth, air past sides."),
        "m":  Entry(exemplar: "moon",   tip: "Lips closed, hum through your nose."),
        "n":  Entry(exemplar: "no",     tip: "Tongue behind teeth, hum through nose."),
        "ŋ":  Entry(exemplar: "sing",   tip: "Back of tongue up, hum through nose."),
        "p":  Entry(exemplar: "pen",    tip: "Press lips, release a puff, no voice."),
        "ɹ":  Entry(exemplar: "red",    tip: "Curl tongue back without touching the roof."),
        "s":  Entry(exemplar: "see",    tip: "Tongue near ridge, hiss air, no voice."),
        "ʃ":  Entry(exemplar: "she",    tip: "Round lips, push air for a \"sh\"."),
        "t":  Entry(exemplar: "top",    tip: "Tongue taps behind teeth, no voice."),
        "θ":  Entry(exemplar: "think",  tip: "Tongue between teeth, blow air, no voice."),
        "v":  Entry(exemplar: "van",    tip: "Top teeth on lower lip, add voice."),
        "w":  Entry(exemplar: "we",     tip: "Round lips tightly, then glide open."),
        "j":  Entry(exemplar: "yes",    tip: "Tongue high front, glide into the vowel."),
        "z":  Entry(exemplar: "zoo",    tip: "Like \"s\" but buzz with your voice."),
        "ʒ":  Entry(exemplar: "vision", tip: "Like \"sh\" but buzz with your voice."),
    ]
}
