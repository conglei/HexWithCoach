//
//  ProgressDigestView.swift
//  HexIOS
//
//  RC-6 weekly digest: the expandable surface behind the Review header. Shows the
//  streak, per-lens levels (only-up), "wins" (mastered patterns), and the next
//  focus. Every metric here is growth-framed — nothing reads as a downgrade. Styled
//  with the shared HexTheme: a gradient streak hero and clean gradient rows.
//

import HexCore
import SwiftUI

struct ProgressDigestView: View {
    let progress: CoachProgress
    @State private var profile = LearnerProfile()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                streakCard

                improvingSection

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
        .task { profile = progress.loadProfile() }
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
                Text("best \(progress.streak.best) day\(progress.streak.best == 1 ? "" : "s")")
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
        let n = progress.streak.current
        return n == 0 ? "Start your streak" : "\(n)-day streak"
    }

    // MARK: - Levels

    private var improvingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("HOW YOU'RE IMPROVING")
            VStack(spacing: 16) {
                ForEach(Lens.allCases, id: \.self) { lens in
                    levelRow(lens)
                }
            }
            .hexCard()
        }
    }

    private func levelRow(_ lens: Lens) -> some View {
        let level = profile.level(for: lens)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(lensDisplayName(lens)).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(level)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(level), total: 100)
                .tint(HexTheme.gradientColors[0])
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
