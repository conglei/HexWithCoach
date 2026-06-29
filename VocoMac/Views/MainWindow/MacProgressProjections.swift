//
//  MacProgressProjections.swift
//  VocoMac
//
//  Pure, deterministic projections of the synced `CoachObservation` log (DM-2) for
//  the macOS Progress digest (MC-R7). The design (macos-companion-phase3-reconcile
//  §4–§5) makes the observation log the *durable substrate*: per-lens trends and
//  per-word pronunciation (GOP) trends are **queries over the dated observation
//  rows**, not values reconstructed from the curated cards or only the profile.
//
//  This struct holds none of its own state and writes nothing back — it only reads
//  an array of `CoachObservation` already fetched (read-only) from the shared
//  `ModelContainer`. Streak / per-lens level / mastered-pattern wins still come
//  from the shared progress types (`ProgressSummary` / `StreakState` /
//  `LearnerProfile`) the way iOS `ProgressDigestView` builds them; these
//  projections add the *time series* the log uniquely enables.
//
//  Buckets are calendar weeks, anchored to the device calendar's start-of-week, so
//  the digest reads as "this week vs the weeks before" — consistent with iOS for
//  the same synced account because the inputs are the same synced rows.
//

import Foundation
import VocoCore

/// Deterministic projections derived purely from the `CoachObservation` log. Same
/// rows in → same projections out (no clock reads beyond the supplied `now`).
struct MacProgressProjections: Equatable {

    // MARK: Per-lens weekly trend

    /// One lens's observation-log trend: how many findings it accrued this week vs
    /// the prior week, plus a short weekly count series for a sparkline. Fewer
    /// findings week-over-week reads as improvement (growth-framed).
    struct LensTrend: Identifiable, Equatable {
        var lens: Lens
        /// Findings dated within the current week bucket.
        var thisWeek: Int
        /// Findings dated within the immediately preceding week bucket.
        var lastWeek: Int
        /// Oldest-first weekly finding counts (for the sparkline), one per bucket.
        var weekly: [WeeklyCount]
        var id: Lens { lens }

        /// Net change this week vs last (negative = fewer findings = improving).
        var delta: Int { thisWeek - lastWeek }

        /// Growth-framed direction. Fewer findings (or none this week after some
        /// last week) = improving; more = "more practice"; equal/none = steady.
        var direction: ProgressSummary.Trend {
            if lastWeek == 0 && thisWeek == 0 { return .new }
            if thisWeek < lastWeek { return .improving }
            return .steady
        }
    }

    /// A single week bucket's count, tagged by the bucket's start date.
    struct WeeklyCount: Identifiable, Equatable {
        var weekStart: Date
        var count: Int
        var id: Date { weekStart }
    }

    // MARK: Per-word GOP trend

    /// A per-word pronunciation (GOP) trend over the objective observations. GOP is
    /// `≤ 0`; closer to 0 = better. `recentMean` vs `earlierMean` shows whether the
    /// word is trending toward clearer (less negative) over time.
    struct WordTrend: Identifiable, Equatable {
        var word: String
        /// Mean GOP over the most recent half of this word's scored observations.
        var recentMean: Double
        /// Mean GOP over the earlier half (empty → equals `recentMean`).
        var earlierMean: Double
        /// Total scored observations for this word.
        var count: Int
        /// Oldest-first GOP series for this word (one point per observation).
        var series: [GOPPoint]
        var id: String { word }

        /// Improvement = recent GOP closer to zero than earlier. Positive = clearer.
        var improvement: Double { recentMean - earlierMean }
        var isImproving: Bool { improvement > 0.01 }
    }

    /// A single dated GOP sample for a word (oldest-first within a `WordTrend`).
    struct GOPPoint: Identifiable, Equatable {
        var date: Date
        var gop: Double
        var id: Date { date }
    }

    // MARK: Fields

    /// Per-lens weekly trends, in `Lens.allCases` order, only for lenses with any
    /// observation. Empty when the log carries no LLM/objective findings yet.
    var lensTrends: [LensTrend]
    /// The learner's most-practiced words by scored-observation count, each with a
    /// GOP trend, worst-recent-first so "sounds to work on" lead. Capped.
    var wordTrends: [WordTrend]
    /// Total findings dated in the current week — the weekly-digest headline.
    var findingsThisWeek: Int
    /// Total findings dated in the prior week — for the week-over-week digest line.
    var findingsLastWeek: Int
    /// Distinct days in the current week that carried at least one finding.
    var activeDaysThisWeek: Int

    var isEmpty: Bool { lensTrends.isEmpty && wordTrends.isEmpty }

    // MARK: Build

    /// How many words to surface in the per-word GOP trend list.
    static let wordTrendLimit = 6
    /// How many weekly buckets to keep in each sparkline series.
    static let weekBucketCount = 6

    /// Project the observation log into the digest's time-series. Pure: depends only
    /// on `observations`, `now`, and the supplied `calendar`.
    static func make(
        observations: [CoachObservation],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MacProgressProjections {
        let weekStart = calendar.startOfWeek(for: now)
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart

        // Oldest-first bucket anchors for the sparklines (current week last).
        let bucketStarts: [Date] = (0..<weekBucketCount).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -7 * back, to: weekStart)
        }

        // MARK: per-lens weekly trends
        var lensTrends: [LensTrend] = []
        for lens in Lens.allCases {
            let rows = observations.filter { $0.lens == lens }
            guard !rows.isEmpty else { continue }

            let thisWeek = rows.filter { $0.date >= weekStart }.count
            let lastWeek = rows.filter { $0.date >= lastWeekStart && $0.date < weekStart }.count

            let weekly = bucketStarts.map { start -> WeeklyCount in
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
                let count = rows.filter { $0.date >= start && $0.date < end }.count
                return WeeklyCount(weekStart: start, count: count)
            }

            lensTrends.append(LensTrend(
                lens: lens, thisWeek: thisWeek, lastWeek: lastWeek, weekly: weekly
            ))
        }

        // MARK: per-word GOP trends (objective lane: rows carry `word` + `gop`)
        let scored = observations
            .filter { $0.word != nil && $0.gop != nil }
            .sorted { $0.date < $1.date }
        var byWord: [String: [(date: Date, gop: Double)]] = [:]
        for row in scored {
            guard let word = row.word, let gop = row.gop else { continue }
            byWord[word, default: []].append((row.date, gop))
        }

        var wordTrends: [WordTrend] = byWord.map { word, samples in
            let sorted = samples.sorted { $0.date < $1.date }
            let mid = sorted.count / 2
            let earlier = sorted.prefix(mid).map(\.gop)
            let recent = sorted.suffix(sorted.count - mid).map(\.gop)
            let recentMean = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
            let earlierMean = earlier.isEmpty ? recentMean : earlier.reduce(0, +) / Double(earlier.count)
            return WordTrend(
                word: word,
                recentMean: recentMean,
                earlierMean: earlierMean,
                count: sorted.count,
                series: sorted.map { GOPPoint(date: $0.date, gop: $0.gop) }
            )
        }
        // Surface the words most worth working on: lowest (worst) recent GOP first,
        // tie-broken by more samples, then word for a stable/diffable order.
        wordTrends.sort {
            ($0.recentMean, -$0.count, $0.word) < ($1.recentMean, -$1.count, $1.word)
        }
        wordTrends = Array(wordTrends.prefix(wordTrendLimit))

        // MARK: weekly digest headline
        let findingsThisWeek = observations.filter { $0.date >= weekStart }.count
        let findingsLastWeek = observations.filter { $0.date >= lastWeekStart && $0.date < weekStart }.count
        let activeDays = Set(
            observations
                .filter { $0.date >= weekStart }
                .map { calendar.startOfDay(for: $0.date) }
        ).count

        return MacProgressProjections(
            lensTrends: lensTrends,
            wordTrends: wordTrends,
            findingsThisWeek: findingsThisWeek,
            findingsLastWeek: findingsLastWeek,
            activeDaysThisWeek: activeDays
        )
    }
}

private extension Calendar {
    /// Start-of-day of the first day of the week containing `date`.
    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? startOfDay(for: date)
    }
}
