import Foundation

// MARK: - Pronunciation signals (compact, per-note summary)

/// A compact, `Codable` summary of a single note's `PronunciationResult`
/// (deep-design §2; ADR-0001). The full per-phoneme result is persisted with the
/// note; this summary is the cheap, aggregate view the calibration corpus and the
/// pattern detector consume, plus what trends/feeds display.
///
/// GOP is `≤ 0` throughout: closer to 0 = the audio confidently matched the
/// expected phoneme; very negative = likely mispronounced. Per ADR-0001, nothing
/// here triggers a pattern by *absolute* value — these are inputs to a
/// per-speaker-relative ranking. Treat any single-note GOP as a hint only.
public struct PronunciationSignals: Codable, Sendable, Equatable {
    /// One phoneme's aggregate GOP within this note.
    public struct PhonemeStat: Codable, Sendable, Equatable {
        /// IPA symbol (matches `PhonemeScore.symbol`).
        public var symbol: String
        /// Mean GOP across every instance of this phoneme in the note (≤ 0).
        public var meanGOP: Double
        /// How many instances of this phoneme the note contained.
        public var count: Int

        public init(symbol: String, meanGOP: Double, count: Int) {
            self.symbol = symbol
            self.meanGOP = meanGOP
            self.count = count
        }
    }

    /// The lowest-scoring phoneme inside a flagged word, for a per-instance hint.
    public struct WorstWord: Codable, Sendable, Equatable {
        public var word: String
        /// The IPA symbol of the word's worst phoneme.
        public var worstPhoneme: String
        /// That phoneme's GOP (≤ 0).
        public var gop: Double

        public init(word: String, worstPhoneme: String, gop: Double) {
            self.word = word
            self.worstPhoneme = worstPhoneme
            self.gop = gop
        }
    }

    /// Mean GOP over all phonemes in the note (≤ 0). Zero when the note had none.
    public var overallGOP: Double
    /// Per-phoneme mean GOP + instance counts, one entry per distinct IPA symbol,
    /// sorted by symbol so the encoding is stable/diffable.
    public var perPhoneme: [PhonemeStat]
    /// The note's lowest-GOP words (a per-instance visual hint, NOT a pattern),
    /// worst-first, capped at `worstWordLimit`.
    public var worstWords: [WorstWord]

    public init(
        overallGOP: Double = 0,
        perPhoneme: [PhonemeStat] = [],
        worstWords: [WorstWord] = []
    ) {
        self.overallGOP = overallGOP
        self.perPhoneme = perPhoneme
        self.worstWords = worstWords
    }

    /// How many worst words to retain per note.
    public static let worstWordLimit = 5

    /// Derive the compact summary from a full per-note result. Pure.
    public init(result: PronunciationResult) {
        let allPhonemes = result.words.flatMap(\.phonemes)
        overallGOP = allPhonemes.isEmpty
            ? 0
            : allPhonemes.map(\.gop).reduce(0, +) / Double(allPhonemes.count)

        // Mean GOP per distinct IPA symbol.
        var sums: [String: (sum: Double, count: Int)] = [:]
        for p in allPhonemes {
            let cur = sums[p.symbol] ?? (0, 0)
            sums[p.symbol] = (cur.sum + p.gop, cur.count + 1)
        }
        perPhoneme = sums
            .map { PhonemeStat(symbol: $0.key, meanGOP: $0.value.sum / Double($0.value.count), count: $0.value.count) }
            .sorted { $0.symbol < $1.symbol }

        // Worst word = each word tagged with its lowest-GOP phoneme; worst-first.
        let tagged: [WorstWord] = result.words.compactMap { word in
            guard let worst = word.phonemes.min(by: { $0.gop < $1.gop }) else { return nil }
            return WorstWord(word: word.word, worstPhoneme: worst.symbol, gop: worst.gop)
        }
        worstWords = Array(tagged.sorted { $0.gop < $1.gop }.prefix(Self.worstWordLimit))
    }
}

// MARK: - Per-speaker GOP calibration

/// Per-speaker baseline GOP statistics, accumulated across the learner's own
/// corpus (ADR-0001: "the per-speaker baseline is recomputed as the corpus
/// grows"). A phoneme is *weak* only relative to this distribution — never by an
/// absolute cutoff — so a stable accent or a quiet mic never reads as an error.
///
/// Pure value type built deterministically from a sequence of per-note
/// `PronunciationSignals`, so the calibration recomputes identically from the
/// same corpus (auditable, no drift).
public struct PronunciationCalibration: Sendable, Equatable {
    /// One phoneme's aggregate distribution across the whole corpus.
    public struct PhonemeBaseline: Sendable, Equatable {
        public var symbol: String
        /// Corpus-wide mean GOP for this phoneme (≤ 0).
        public var meanGOP: Double
        /// Total instances seen across the corpus.
        public var totalCount: Int
        /// Number of distinct notes this phoneme appeared in.
        public var noteCount: Int

        public init(symbol: String, meanGOP: Double, totalCount: Int, noteCount: Int) {
            self.symbol = symbol
            self.meanGOP = meanGOP
            self.totalCount = totalCount
            self.noteCount = noteCount
        }
    }

    /// Corpus-wide mean GOP over every phoneme instance (the speaker's baseline).
    public let corpusMeanGOP: Double
    /// Per-phoneme baselines, sorted by symbol.
    public let baselines: [PhonemeBaseline]
    /// Number of notes that contributed to this calibration.
    public let noteCount: Int

    public init(corpusMeanGOP: Double, baselines: [PhonemeBaseline], noteCount: Int) {
        self.corpusMeanGOP = corpusMeanGOP
        self.baselines = baselines
        self.noteCount = noteCount
    }

    /// Build a calibration from the learner's corpus of per-note signals. Pure.
    public init(corpus: [PronunciationSignals]) {
        noteCount = corpus.count

        // Weighted corpus mean (each phoneme instance counts once).
        var corpusSum = 0.0
        var corpusN = 0
        var acc: [String: (sum: Double, total: Int, notes: Int)] = [:]
        for note in corpus {
            for stat in note.perPhoneme {
                corpusSum += stat.meanGOP * Double(stat.count)
                corpusN += stat.count
                let cur = acc[stat.symbol] ?? (0, 0, 0)
                acc[stat.symbol] = (cur.sum + stat.meanGOP * Double(stat.count), cur.total + stat.count, cur.notes + 1)
            }
        }
        corpusMeanGOP = corpusN > 0 ? corpusSum / Double(corpusN) : 0
        baselines = acc
            .map { PhonemeBaseline(symbol: $0.key, meanGOP: $0.value.sum / Double($0.value.total), totalCount: $0.value.total, noteCount: $0.value.notes) }
            .sorted { $0.symbol < $1.symbol }
    }

    /// Rank of a phoneme's baseline GOP within the speaker's own distribution,
    /// as a fraction in `0...1` where 0 = the worst (lowest GOP) phoneme and 1 =
    /// the best. Used by the detector for *relative* (never absolute) flagging.
    /// nil when the symbol isn't in the corpus.
    public func relativeRank(of symbol: String) -> Double? {
        guard !baselines.isEmpty, baselines.contains(where: { $0.symbol == symbol }) else { return nil }
        let sorted = baselines.map(\.meanGOP).sorted()   // ascending: worst first
        guard let target = baselines.first(where: { $0.symbol == symbol })?.meanGOP else { return nil }
        // How many baselines are strictly worse than this one.
        let worseCount = sorted.filter { $0 < target }.count
        let denom = max(1, baselines.count - 1)
        return Double(worseCount) / Double(denom)
    }

    /// Whether `symbol` is a *relative outlier* among the speaker's own phonemes:
    /// its baseline GOP sits more than `stdMultiplier` standard deviations below
    /// the speaker's MEAN phoneme GOP. This is the load-bearing ADR-0001 guarantee
    /// — mean and σ are computed purely from the speaker's own distribution, so a
    /// uniformly low (quiet-mic / accent) distribution has σ ≈ 0 and flags NOTHING,
    /// while a phoneme that stands out as the speaker's own worst is caught.
    /// `false` when the symbol isn't in the corpus or the distribution is too
    /// small/degenerate to judge.
    public func isRelativeOutlier(_ symbol: String, stdMultiplier: Double = 1.0) -> Bool {
        let gops = baselines.map(\.meanGOP)
        guard gops.count >= 4, let target = baselines.first(where: { $0.symbol == symbol })?.meanGOP else { return false }
        let mean = gops.reduce(0, +) / Double(gops.count)
        let variance = gops.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(gops.count)
        let std = variance.squareRoot()
        // Degenerate / near-uniform distribution: no genuine separation exists, so
        // nothing is an outlier (absolute GOP must never trigger a pattern).
        guard std > 1e-6 else { return false }
        return target < mean - stdMultiplier * std
    }
}

// MARK: - Pronunciation pattern detector (pure, deterministic)

/// Turns per-speaker GOP calibration + recurrence into pronunciation
/// `RecurringPattern`s, deterministically and with NO LLM (ADR-0001).
///
/// A phoneme becomes a flagged pattern ONLY when ALL of these hold:
///   1. **Cold-start gate** — the corpus has at least `minNotes` notes. Below
///      that, the per-speaker baseline isn't trustworthy, so we emit nothing.
///   2. **Per-speaker-relative ranking** — the phoneme ranks among the learner's
///      OWN worst (`relativeRank ≤ relativeRankCutoff`) AND stands out as a
///      relative outlier in their own distribution (median + MAD). Absolute GOP is
///      never consulted for the decision — a uniformly low (quiet-mic / accent)
///      distribution has no outliers and flags nothing. Absolute GOP feeds only
///      the per-instance worst-word hint.
///   3. **Recurrence** — the phoneme is among the note's weakest in at least
///      `minInstances` (K) instances spread over at least `minRecurringNotes` (N)
///      distinct notes.
///
/// The baseline recomputes as the corpus grows (`PronunciationCalibration`), so a
/// flag can clear as the learner improves and the corpus shifts.
public enum PronunciationPatternDetector {

    // MARK: Constants (conservative; documented; tunable on real corpora — see
    // design §8 open item 1).

    /// Cold-start gate: no patterns until the corpus has at least this many notes.
    /// The per-speaker baseline is too noisy below this to rank reliably.
    public static let minNotes = 5

    /// Recurrence K: a phoneme must appear among a note's weakest in at least this
    /// many instances (summed across notes) to count as recurring.
    public static let minInstances = 4

    /// Recurrence N: ...and those instances must span at least this many distinct
    /// notes (so one chatty note can't manufacture a pattern).
    public static let minRecurringNotes = 3

    /// Per-speaker-relative cutoff: a phoneme's baseline GOP must rank in the
    /// bottom this fraction of the learner's OWN phoneme distribution. 0.25 = the
    /// worst quarter. Conservative; relative, never absolute.
    public static let relativeRankCutoff = 0.25

    /// How many standard deviations below the speaker's mean phoneme GOP a phoneme
    /// must sit to count as a relative outlier. 1.0 ≈ "clearly one of my worst",
    /// while a uniform distribution (σ ≈ 0) never qualifies.
    public static let outlierStdMultiplier = 1.0

    /// Within a single note, a phoneme counts as "weak in this note" when its
    /// per-note mean GOP is at or below this percentile of THAT note's phonemes.
    /// Purely relative to the note itself — used only to count recurrence
    /// instances, not to decide a pattern.
    public static let perNoteWeakPercentile = 0.25

    /// A note in the detector's corpus: its signals plus the transcript id, so a
    /// flagged pattern can carry the learner's own example back into the profile.
    public struct Note: Sendable, Equatable {
        public var transcriptID: UUID
        public var signals: PronunciationSignals
        public init(transcriptID: UUID, signals: PronunciationSignals) {
            self.transcriptID = transcriptID
            self.signals = signals
        }
    }

    /// Canonical dedupe key for a phoneme pattern, stable across runs so the
    /// profile merges recurrences (mirrors `RecurringPattern.key` semantics).
    public static func key(forPhoneme symbol: String) -> String { "pron-phoneme-\(symbol)" }

    /// Detect pronunciation patterns over the learner's whole corpus and return
    /// them as `VerifiedObservation`s ready for `LearnerProfile.integrate`.
    /// Deterministic + pure: same corpus in → same observations out.
    public static func detect(corpus: [Note]) -> [VerifiedObservation] {
        let calibration = PronunciationCalibration(corpus: corpus.map(\.signals))

        // Cold-start gate.
        guard calibration.noteCount >= minNotes else { return [] }

        // Recurrence: for each phoneme, count weak instances and the notes they
        // span. A phoneme is "weak in a note" when its per-note mean GOP sits at
        // or below the note's own weak percentile (relative to that note).
        struct Recurrence { var instances = 0; var notes = Set<UUID>(); var example: (id: UUID, word: String)? }
        var recur: [String: Recurrence] = [:]

        for note in corpus {
            let stats = note.signals.perPhoneme
            guard !stats.isEmpty else { continue }
            let threshold = weakThreshold(forNoteGOPs: stats.map(\.meanGOP))
            // Strictly below the note's own weak threshold, so a uniform note
            // (every phoneme equal) marks nothing as weak.
            for stat in stats where stat.meanGOP < threshold {
                var r = recur[stat.symbol] ?? Recurrence()
                r.instances += stat.count
                r.notes.insert(note.transcriptID)
                if r.example == nil {
                    let exampleWord = note.signals.worstWords.first(where: { $0.worstPhoneme == stat.symbol })?.word
                    r.example = (note.transcriptID, exampleWord ?? stat.symbol)
                }
                recur[stat.symbol] = r
            }
        }

        var observations: [VerifiedObservation] = []
        for (symbol, r) in recur.sorted(by: { $0.key < $1.key }) {
            // Recurrence gate (K instances over N notes).
            guard r.instances >= minInstances, r.notes.count >= minRecurringNotes else { continue }
            // Per-speaker-relative gate: among the learner's OWN worst phonemes AND
            // a genuine relative outlier (so uniform/accent distributions, where
            // absolute GOP is low everywhere, never trigger a pattern).
            guard let rank = calibration.relativeRank(of: symbol), rank <= relativeRankCutoff else { continue }
            guard calibration.isRelativeOutlier(symbol, stdMultiplier: outlierStdMultiplier) else { continue }
            guard let example = r.example else { continue }

            observations.append(VerifiedObservation(
                lens: .pronunciation,
                key: key(forPhoneme: symbol),
                summary: "Recurring difficulty with the /\(symbol)/ sound",
                rule: "The /\(symbol)/ sound repeatedly ranks among your weakest. Targeted practice can sharpen it.",
                severity: 3,
                example: ExampleRef(transcriptID: example.id, span: example.word),
                inferredL1: nil
            ))
        }
        return observations
    }

    /// The per-note weak-GOP threshold: the value at `perNoteWeakPercentile` of
    /// the note's ascending per-phoneme mean GOPs (relative to the note itself).
    static func weakThreshold(forNoteGOPs gops: [Double]) -> Double {
        guard !gops.isEmpty else { return 0 }
        let sorted = gops.sorted()    // ascending: worst first
        let idx = Int((Double(sorted.count - 1) * perNoteWeakPercentile).rounded(.down))
        return sorted[max(0, min(sorted.count - 1, idx))]
    }
}
