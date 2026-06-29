//
//  MacProgressView.swift
//  VocoMac
//
//  The macOS Progress digest (MC-R7) — the third surface of the Coach hub. Mirrors
//  the iOS `ProgressDigestView` natively, but re-founded on the synced
//  `CoachObservation` log (design §4–§5): per-lens trends and per-word
//  pronunciation (GOP) trends are **queries over the dated observation rows** (via
//  `MacProgressProjections`), while the streak, per-lens levels, mastered-pattern
//  "wins", and the pronunciation GOP summary reuse the shared `ProgressSummary` /
//  `StreakState` / `LearnerProfile` types the way iOS does.
//
//  Where the metrics come from:
//    • Per-lens *weekly* deltas/trends  → `CoachObservation` query (this file).
//    • Per-word GOP trends              → `CoachObservation` query (this file).
//    • Weekly digest (findings, active days) → `CoachObservation` query.
//    • Streak (never-punishing)         → shared `StreakState` (CoachStreakStore).
//    • Per-lens *level* + mastered wins → shared `ProgressSummary` over the
//      file-backed `LearnerProfile` (same store `MacCoachService` writes).
//    • Pronunciation GOP summary        → shared `ProgressSummary` over the per-note
//      `PronunciationSignals` persisted with each `TranscriptEntry` (CI-3).
//
//  READ-ONLY: this view loads the profile/streak/observation rows and renders. It
//  never mutates the coach state, never writes the streak, never inserts rows.
//
//  Native, not touch: a scrollable multi-section digest, Swift Charts sparklines /
//  bars for the trends, hoverable cards, sized for the companion window.
//

import Charts
import SwiftData
import SwiftUI
import VocoCore

struct MacProgressView: View {
    /// Read-only: dated coaching findings (DM-2). Newest-first; the projection
    /// re-sorts as needed. Drives per-lens + per-word trends and the weekly digest.
    @Query(sort: \CoachObservation.date, order: .reverse) private var observations: [CoachObservation]
    /// Read-only: notes carry the per-note pronunciation summary (CI-3) the shared
    /// `ProgressSummary` consumes for its GOP roll-up.
    @Query(sort: \TranscriptEntry.date, order: .reverse) private var transcripts: [TranscriptEntry]

    /// Built from the file-backed `LearnerProfile` + the App-Group streak, the same
    /// way `MacCoachService` and iOS `CoachProgress` resolve them. Recomputed on
    /// appear and whenever the synced rows change.
    @State private var summary = ProgressSummary(
        lenses: [], pronunciation: .init(), streak: StreakState(), totalWins: 0
    )
    @State private var profile = LearnerProfile()

    /// Pure projection of the observation log (per-lens + per-word trends, digest).
    private var projections: MacProgressProjections {
        MacProgressProjections.make(observations: observations)
    }

    var body: some View {
        Group {
            if hasAnything {
                digest
            } else {
                empty
            }
        }
        .task { reload() }
        // Recompute the shared roll-up whenever the synced inputs change so the
        // digest stays consistent with the same account on iOS.
        .onChange(of: observations.count) { _, _ in reload() }
        .onChange(of: transcripts.count) { _, _ in reload() }
    }

    /// Resolve the shared progress types read-only — never writes the streak or profile.
    private func reload() {
        profile = MacCoachProgressStore.loadProfile()
        let streak = MacCoachProgressStore.loadStreak()
        let corpus = transcripts.compactMap(\.pronunciationSignals)
        summary = ProgressSummary.make(profile: profile, streak: streak, pronunciationCorpus: corpus)
    }

    private var hasAnything: Bool {
        summary.streak.current > 0
            || summary.totalWins > 0
            || !projections.isEmpty
            || summary.pronunciation.hasData
            || summary.lenses.contains { $0.level > 0 }
    }

    // MARK: - Digest

    private var digest: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                streakCard
                weeklyDigestCard
                lensTrendsSection
                if summary.pronunciation.hasData || !projections.wordTrends.isEmpty {
                    pronunciationSection
                }
                if !mastered.isEmpty {
                    winsSection
                }
                if let focus = nextFocus {
                    focusSection(focus)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Streak hero (shared StreakState)

    private var streakCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(streakText).font(.title3.weight(.bold))
                Text(streakSubtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.tint.opacity(0.18))
        )
    }

    private var streakText: String {
        let n = summary.streak.current
        return n == 0 ? "Start your streak" : "\(n)-day streak"
    }

    private var streakSubtitle: String {
        let best = summary.streak.best
        let bestText = "best \(best) day\(best == 1 ? "" : "s")"
        return summary.totalWins > 0
            ? "\(bestText) · \(summary.totalWins) win\(summary.totalWins == 1 ? "" : "s")"
            : bestText
    }

    // MARK: - Weekly digest (CoachObservation query)

    private var weeklyDigestCard: some View {
        let p = projections
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("THIS WEEK")
            HStack(spacing: 16) {
                digestStat(
                    value: "\(p.findingsThisWeek)",
                    label: "coachable moments",
                    delta: deltaText(this: p.findingsThisWeek, last: p.findingsLastWeek)
                )
                Divider().frame(height: 36)
                digestStat(value: "\(p.activeDaysThisWeek)", label: "active day\(p.activeDaysThisWeek == 1 ? "" : "s")", delta: nil)
            }
            .hexMacCard()
        }
    }

    private func digestStat(value: String, label: String, delta: (text: String, improving: Bool)?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.title.weight(.semibold)).monospacedDigit()
                if let delta {
                    Label(delta.text, systemImage: delta.improving ? "arrow.down.right" : "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(delta.improving ? .green : .secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fewer findings this week reads as improvement (growth-framed).
    private func deltaText(this: Int, last: Int) -> (text: String, improving: Bool)? {
        guard last > 0 || this > 0 else { return nil }
        let diff = this - last
        if diff == 0 { return ("same as last week", false) }
        return ("\(abs(diff)) vs last week", diff < 0)
    }

    // MARK: - Per-lens trends (CoachObservation query + shared level)

    private var lensTrendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("HOW YOU'RE IMPROVING")
            VStack(spacing: 16) {
                ForEach(summary.lenses.filter { lensIsShown($0) }) { lens in
                    lensRow(lens)
                }
            }
            .hexMacCard()
        }
    }

    /// Show a lens if it has a level, profile patterns, or any observation-log trend.
    private func lensIsShown(_ lens: ProgressSummary.LensProgress) -> Bool {
        lens.level > 0 || lens.mastered > 0 || lens.improving > 0 || lens.active > 0
            || trend(for: lens.lens) != nil
    }

    private func trend(for lens: Lens) -> MacProgressProjections.LensTrend? {
        projections.lensTrends.first { $0.lens == lens }
    }

    private func lensRow(_ lens: ProgressSummary.LensProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(macLensDisplayName(lens.lens)).font(.subheadline.weight(.medium))
                lensTrendBadge(lens)
                Spacer()
                if let t = trend(for: lens.lens) {
                    lensSparkline(t)
                }
                Text("\(lens.level)")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
            ProgressView(value: Double(lens.level), total: 100).tint(Color.accentColor)
        }
    }

    /// Trend badge — prefers the observation-log week-over-week direction (the
    /// point of MC-R7), falling back to the profile's mastered "wins" count.
    @ViewBuilder
    private func lensTrendBadge(_ lens: ProgressSummary.LensProgress) -> some View {
        if let t = trend(for: lens.lens), t.lastWeek > 0, t.delta < 0 {
            Label("\(abs(t.delta)) fewer this week", systemImage: "arrow.down.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
        } else if lens.mastered > 0 {
            Label("\(lens.mastered) win\(lens.mastered == 1 ? "" : "s")", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
        } else if lens.trend == .improving {
            Label("improving", systemImage: "arrow.up.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
        } else {
            EmptyView()
        }
    }

    /// A tiny weekly-count sparkline from the observation-log buckets.
    private func lensSparkline(_ t: MacProgressProjections.LensTrend) -> some View {
        Chart(t.weekly) { bucket in
            LineMark(x: .value("Week", bucket.weekStart), y: .value("Findings", bucket.count))
                .interpolationMethod(.monotone)
                .foregroundStyle(.tint)
            AreaMark(x: .value("Week", bucket.weekStart), y: .value("Findings", bucket.count))
                .interpolationMethod(.monotone)
                .foregroundStyle(.tint.opacity(0.12))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(width: 72, height: 24)
    }

    // MARK: - Pronunciation (shared GOP summary + per-word CoachObservation trends)

    private var pronunciationSection: some View {
        let pron = summary.pronunciation
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PRONUNCIATION")
            VStack(alignment: .leading, spacing: 12) {
                if pron.hasData {
                    HStack {
                        Text("Across \(pron.noteCount) note\(pron.noteCount == 1 ? "" : "s")")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if pron.masteredPhonemes > 0 {
                            Label("\(pron.masteredPhonemes) sound\(pron.masteredPhonemes == 1 ? "" : "s") mastered",
                                  systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    if !pron.weakestPhonemes.isEmpty {
                        Text("Sounds to keep practicing").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(pron.weakestPhonemes, id: \.symbol) { p in
                                Text("/\(p.symbol)/")
                                    .font(.footnote.weight(.semibold).monospaced())
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.tint.opacity(0.10), in: Capsule())
                            }
                        }
                    }
                }

                // Per-word GOP trends — the observation-log query. These show whether
                // specific words are getting clearer over time, which the profile
                // alone can't express.
                if !projections.wordTrends.isEmpty {
                    if pron.hasData { Divider() }
                    Text("Words you're working on").font(.caption).foregroundStyle(.secondary)
                    ForEach(projections.wordTrends) { word in
                        wordTrendRow(word)
                    }
                }
            }
            .hexMacCard()
        }
    }

    private func wordTrendRow(_ word: MacProgressProjections.WordTrend) -> some View {
        HStack(spacing: 12) {
            Text(word.word)
                .font(.callout.weight(.medium))
                .frame(minWidth: 80, alignment: .leading)
            wordGOPChart(word)
            Spacer()
            if word.count >= 2 {
                Label(
                    word.isImproving ? "clearer" : "keep going",
                    systemImage: word.isImproving ? "arrow.up.right" : "waveform"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(word.isImproving ? .green : .secondary)
            }
            Text("\(word.count)×")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    /// GOP series for one word (≤ 0; rising toward 0 = clearer). Points-and-line so a
    /// single observation still renders.
    private func wordGOPChart(_ word: MacProgressProjections.WordTrend) -> some View {
        Chart(word.series) { point in
            LineMark(x: .value("When", point.date), y: .value("GOP", point.gop))
                .interpolationMethod(.monotone)
                .foregroundStyle(word.isImproving ? Color.green : Color.accentColor)
            PointMark(x: .value("When", point.date), y: .value("GOP", point.gop))
                .symbolSize(18)
                .foregroundStyle(word.isImproving ? Color.green : Color.accentColor)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(width: 120, height: 28)
    }

    // MARK: - Wins (shared LearnerProfile)

    private var winsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("WINS")
            VStack(spacing: 12) {
                ForEach(mastered) { pattern in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mastered \(pattern.summary)").font(.subheadline.weight(.medium))
                            Text("milestone unlocked").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .hexMacCard()
        }
    }

    // MARK: - Next focus (shared LearnerProfile)

    private func focusSection(_ focus: RecurringPattern) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("FOCUS NEXT")
            VStack(alignment: .leading, spacing: 4) {
                Text(focus.summary).font(.subheadline.weight(.semibold))
                Text(focus.rule).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Empty

    private var empty: some View {
        ContentUnavailableView {
            Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Your streak, per-lens trends, and pronunciation progress will appear here as you keep speaking.")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold)).tracking(1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mastered: [RecurringPattern] { profile.patterns.filter { $0.status == .mastered } }

    private var nextFocus: RecurringPattern? {
        profile.patterns
            .filter { $0.status != .mastered }
            .max { $0.frequency < $1.frequency }
    }
}

// MARK: - Shared-progress read-through (read-only)

/// Resolves the file-backed `LearnerProfile` and the App-Group `StreakState` the
/// same way `MacCoachService` / iOS `CoachProgress` do — but **read-only**. The
/// Progress digest never advances the streak or writes the profile; the streak is
/// counted on review/shadow elsewhere.
private enum MacCoachProgressStore {
    private static var coachDir: URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HexAppGroup.identifier)?
            .appendingPathComponent("Coach", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
    }

    static func loadProfile() -> LearnerProfile {
        LearnerProfileStore(url: coachDir.appendingPathComponent("profile.json")).load()
    }

    static func loadStreak() -> StreakState {
        CoachStreakStore.load()
    }
}

/// Shared, user-facing label for a coaching lens (mirrors iOS `lensDisplayName`,
/// kept local to VocoMac so it doesn't collide with the iOS-module copy).
func macLensDisplayName(_ lens: Lens) -> String {
    switch lens {
    case .grammar: "Grammar"
    case .lexis: "Word choice"
    case .discourse: "Clarity"
    case .pronunciation: "Pronunciation"
    case .prosody: "Fluency"
    }
}

// MARK: - Card styling

private extension View {
    /// Neutral card chrome consistent with `MacCoachCardView` (secondary background +
    /// hairline border), so the digest reads as part of the same hub.
    func hexMacCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4))
            )
    }
}
