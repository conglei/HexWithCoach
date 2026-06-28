import Foundation

// MARK: - Progress summary (CI-12)

/// A pure, deterministic roll-up of cross-lens progress for the Review → Progress
/// surface (design §5): per-lens levels, mastered-pattern counts ("wins"), a
/// pronunciation GOP summary, and the review streak — all derived from data the
/// engine already persists. No LLM, no network, no new persistence.
///
/// Built only from a `LearnerProfile` (per-lens levels + `RecurringPattern`
/// status/frequency/recency), the `StreakState`, and the corpus of per-note
/// `PronunciationSignals` already persisted with each transcript (CI-3). It
/// touches nothing else and writes nothing back.
///
/// **Trend caveat:** per-note *fluency* history (WPM / filler / pause timelines)
/// is not persisted — only the profile's pattern history and the per-note
/// pronunciation signals are. So the non-pronunciation lens trends are derived
/// from the profile's pattern status mix (mastered/improving vs active) rather
/// than from a true time series. The pronunciation lens additionally surfaces an
/// objective GOP summary because its per-note signals *are* readable. When
/// per-note fluency history is persisted later, `LensProgress.trend` for the
/// prosody/fluency lens can be upgraded to a real slope.
public struct ProgressSummary: Sendable, Equatable {

    // MARK: Trend direction

    /// The growth-framed direction for a single lens. Never reads as a downgrade:
    /// a lens with no signal is `.steady`, not negative.
    public enum Trend: String, Sendable, Equatable {
        /// Recent wins or improving patterns — net forward motion.
        case improving
        /// No mastered/improving patterns yet, or only active ones — holding.
        case steady
        /// Brand-new lens with no level and no patterns — nothing measured yet.
        case new
    }

    // MARK: Per-lens progress

    /// One lens's roll-up. `level` is the profile's only-up level; `mastered` and
    /// `improving` are counts of that lens's patterns by status; `active` counts
    /// patterns still recurring. `trend` is the growth-framed direction.
    public struct LensProgress: Sendable, Equatable, Identifiable {
        public var lens: Lens
        public var level: Int
        public var mastered: Int
        public var improving: Int
        public var active: Int
        public var trend: Trend

        public var id: Lens { lens }

        public init(
            lens: Lens,
            level: Int,
            mastered: Int,
            improving: Int,
            active: Int,
            trend: Trend
        ) {
            self.lens = lens
            self.level = level
            self.mastered = mastered
            self.improving = improving
            self.active = active
            self.trend = trend
        }
    }

    // MARK: Pronunciation GOP summary

    /// An objective pronunciation roll-up over the learner's persisted per-note
    /// `PronunciationSignals` (CI-3). GOP is `≤ 0`; closer to 0 = better. This is
    /// the one lens with a real objective time series available, so it gets a
    /// dedicated summary. nil overall is impossible — when the corpus is empty,
    /// `noteCount == 0` and the view can hide it.
    public struct PronunciationProgress: Sendable, Equatable {
        /// Number of notes that carried a pronunciation result.
        public var noteCount: Int
        /// Corpus-wide mean GOP over every phoneme instance (≤ 0). Zero when empty.
        public var meanGOP: Double
        /// The learner's own weakest phonemes by corpus baseline GOP, worst-first,
        /// capped at `weakestPhonemeLimit`. Empty until the cold-start gate clears.
        public var weakestPhonemes: [WeakPhoneme]
        /// Count of mastered pronunciation patterns in the profile (phoneme wins).
        public var masteredPhonemes: Int

        public init(
            noteCount: Int = 0,
            meanGOP: Double = 0,
            weakestPhonemes: [WeakPhoneme] = [],
            masteredPhonemes: Int = 0
        ) {
            self.noteCount = noteCount
            self.meanGOP = meanGOP
            self.weakestPhonemes = weakestPhonemes
            self.masteredPhonemes = masteredPhonemes
        }

        public var hasData: Bool { noteCount > 0 }
    }

    /// A single weak phoneme entry in the GOP summary.
    public struct WeakPhoneme: Sendable, Equatable {
        public var symbol: String
        /// Corpus baseline mean GOP for this phoneme (≤ 0).
        public var meanGOP: Double

        public init(symbol: String, meanGOP: Double) {
            self.symbol = symbol
            self.meanGOP = meanGOP
        }
    }

    // MARK: Fields

    /// Per-lens roll-ups, one per `Lens.allCases`, in `Lens.allCases` order.
    public var lenses: [LensProgress]
    /// The objective pronunciation roll-up.
    public var pronunciation: PronunciationProgress
    /// The review streak, carried through verbatim.
    public var streak: StreakState
    /// Total mastered patterns across every lens (the headline "wins" count).
    public var totalWins: Int

    public init(
        lenses: [LensProgress],
        pronunciation: PronunciationProgress,
        streak: StreakState,
        totalWins: Int
    ) {
        self.lenses = lenses
        self.pronunciation = pronunciation
        self.streak = streak
        self.totalWins = totalWins
    }

    /// Convenience accessor for a single lens's roll-up.
    public func progress(for lens: Lens) -> LensProgress? {
        lenses.first { $0.lens == lens }
    }
}

// MARK: - Builder

public extension ProgressSummary {

    /// How many weakest phonemes to surface in the GOP summary.
    static let weakestPhonemeLimit = 3

    /// Build the summary purely from already-persisted inputs. Deterministic:
    /// same profile + streak + corpus in → same summary out.
    ///
    /// - Parameters:
    ///   - profile: the engine's `LearnerProfile` (levels + patterns).
    ///   - streak: the review streak.
    ///   - pronunciationCorpus: the per-note `PronunciationSignals` already
    ///     persisted with transcripts (CI-3). Pass an empty array when no notes
    ///     carry pronunciation results — the GOP summary then reports `hasData == false`.
    static func make(
        profile: LearnerProfile,
        streak: StreakState,
        pronunciationCorpus: [PronunciationSignals] = []
    ) -> ProgressSummary {
        let lenses: [LensProgress] = Lens.allCases.map { lens in
            let forLens = profile.patterns.filter { $0.lens == lens }
            let mastered = forLens.filter { $0.status == .mastered }.count
            let improving = forLens.filter { $0.status == .improving }.count
            let active = forLens.filter { $0.status == .active }.count
            let level = profile.level(for: lens)

            // Growth-framed trend, derived from the pattern status mix (see the
            // type-level caveat: no per-note fluency time series is persisted).
            let trend: Trend
            if mastered > 0 || improving > 0 {
                trend = .improving
            } else if level <= 0, forLens.isEmpty {
                trend = .new
            } else {
                trend = .steady
            }

            return LensProgress(
                lens: lens,
                level: level,
                mastered: mastered,
                improving: improving,
                active: active,
                trend: trend
            )
        }

        let pronunciation = makePronunciation(profile: profile, corpus: pronunciationCorpus)
        let totalWins = profile.patterns.filter { $0.status == .mastered }.count

        return ProgressSummary(
            lenses: lenses,
            pronunciation: pronunciation,
            streak: streak,
            totalWins: totalWins
        )
    }

    /// Objective GOP roll-up over the persisted per-note signals. Reuses
    /// `PronunciationCalibration` (the same per-speaker baseline the detector
    /// uses) so the weakest phonemes shown match how patterns are actually flagged.
    private static func makePronunciation(
        profile: LearnerProfile,
        corpus: [PronunciationSignals]
    ) -> PronunciationProgress {
        let masteredPhonemes = profile.patterns
            .filter { $0.lens == .pronunciation && $0.status == .mastered }
            .count

        guard !corpus.isEmpty else {
            return PronunciationProgress(masteredPhonemes: masteredPhonemes)
        }

        let calibration = PronunciationCalibration(corpus: corpus)
        // Weakest = lowest baseline GOP first (most negative). Ties broken by
        // symbol so the ordering is stable/diffable.
        let weakest = calibration.baselines
            .sorted { ($0.meanGOP, $0.symbol) < ($1.meanGOP, $1.symbol) }
            .prefix(weakestPhonemeLimit)
            .map { WeakPhoneme(symbol: $0.symbol, meanGOP: $0.meanGOP) }

        return PronunciationProgress(
            noteCount: calibration.noteCount,
            meanGOP: calibration.corpusMeanGOP,
            weakestPhonemes: Array(weakest),
            masteredPhonemes: masteredPhonemes
        )
    }
}
