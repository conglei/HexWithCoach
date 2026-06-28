//
//  ProgressDigestView.swift
//  HexIOS
//
//  RC-6 weekly digest, extended for CI-12: the expandable surface behind the
//  Review header. Shows the streak, per-lens levels + objective trends, a
//  pronunciation GOP summary, "wins" (mastered patterns), and the next focus.
//  Every metric here is growth-framed — nothing reads as a downgrade. The
//  trend/aggregation math is the pure `ProgressSummary` helper (HexCore); this
//  view only renders it. Styled with the shared HexTheme.
//

import HexCore
import SwiftData
import SwiftUI

struct ProgressDigestView: View {
    let progress: CoachProgress

    /// Persisted transcripts — read-only — so we can derive the pronunciation GOP
    /// summary from per-note signals already stored with each note (CI-3). No new
    /// persistence is introduced.
    @Query private var transcripts: [TranscriptEntry]

    @State private var profile = LearnerProfile()
    @State private var summary = ProgressSummary(
        lenses: [], pronunciation: .init(), streak: StreakState(), totalWins: 0
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                streakCard

                improvingSection

                if summary.pronunciation.hasData {
                    pronunciationSection
                }

                if !mastered.isEmpty {
                    winsSection
                }

                if let focus = nextFocus {
                    focusSection(focus)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
    }

    private func reload() {
        profile = progress.loadProfile()
        let corpus = transcripts.compactMap(\.pronunciationSignals)
        summary = progress.summary(pronunciationCorpus: corpus)
    }

    // MARK: - Streak hero

    private var streakCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(streakText)
                    .font(.title3.weight(.bold))
                Text(streakSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(HexTheme.gradient, in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous))
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

    // MARK: - Levels + trends

    private var improvingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("HOW YOU'RE IMPROVING")
            VStack(spacing: 16) {
                ForEach(summary.lenses) { lens in
                    levelRow(lens)
                }
            }
            .hexCard()
        }
    }

    private func levelRow(_ lens: ProgressSummary.LensProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(lensDisplayName(lens.lens)).font(.subheadline.weight(.medium))
                trendBadge(lens)
                Spacer()
                Text("\(lens.level)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(lens.level), total: 100)
                .tint(HexTheme.gradientColors[0])
        }
    }

    @ViewBuilder
    private func trendBadge(_ lens: ProgressSummary.LensProgress) -> some View {
        switch lens.trend {
        case .improving:
            let wins = lens.mastered
            Label(wins > 0 ? "\(wins) win\(wins == 1 ? "" : "s")" : "improving", systemImage: "arrow.up.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(HexTheme.gradientColors[0])
        case .steady, .new:
            EmptyView()
        }
    }

    // MARK: - Pronunciation GOP summary (CI-12)

    private var pronunciationSection: some View {
        let pron = summary.pronunciation
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PRONUNCIATION")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Across \(pron.noteCount) note\(pron.noteCount == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if pron.masteredPhonemes > 0 {
                        Label("\(pron.masteredPhonemes) sound\(pron.masteredPhonemes == 1 ? "" : "s") mastered",
                              systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HexTheme.gradientColors[0])
                    }
                }
                if !pron.weakestPhonemes.isEmpty {
                    Text("Sounds to keep practicing")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(pron.weakestPhonemes, id: \.symbol) { p in
                            Text("/\(p.symbol)/")
                                .font(.footnote.weight(.semibold).monospaced())
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(HexTheme.gradientSoft, in: Capsule())
                        }
                    }
                }
            }
            .hexCard()
        }
    }

    // MARK: - Wins

    private var winsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("WINS")
            VStack(spacing: 12) {
                ForEach(mastered) { pattern in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(HexTheme.gradient)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mastered \(pattern.summary)").font(.subheadline.weight(.medium))
                            Text("milestone unlocked").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .hexCard()
        }
    }

    // MARK: - Next focus

    private func focusSection(_ focus: RecurringPattern) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("FOCUS NEXT")
            VStack(alignment: .leading, spacing: 4) {
                Text(focus.summary).font(.subheadline.weight(.semibold))
                Text(focus.rule).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous))
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

/// Shared, user-facing label for a coaching lens.
func lensDisplayName(_ lens: Lens) -> String {
    switch lens {
    case .grammar: "Grammar"
    case .lexis: "Word choice"
    case .discourse: "Clarity"
    case .pronunciation: "Pronunciation"
    case .prosody: "Fluency"
    }
}
