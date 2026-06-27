//
//  ProgressDigestView.swift
//  HexIOS
//
//  RC-6 weekly digest: the expandable surface behind the Review header. Shows the
//  streak, per-lens levels (only-up), "wins" (mastered patterns), and the next
//  focus. Every metric here is growth-framed — nothing reads as a downgrade.
//

import HexCore
import SwiftUI

struct ProgressDigestView: View {
    let progress: CoachProgress
    @State private var profile = LearnerProfile()

    var body: some View {
        List {
            Section("Streak") {
                LabeledContent("Current", value: "\(progress.streak.current) day\(progress.streak.current == 1 ? "" : "s")")
                LabeledContent("Best", value: "\(progress.streak.best)")
            }

            Section("Levels") {
                ForEach(Lens.allCases, id: \.self) { lens in
                    levelRow(lens)
                }
            }

            if !mastered.isEmpty {
                Section("Wins") {
                    ForEach(mastered) { pattern in
                        Label(pattern.summary, systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            if let focus = nextFocus {
                Section("Next focus") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focus.summary)
                        Text(focus.rule).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .task { profile = progress.loadProfile() }
    }

    private var mastered: [RecurringPattern] { profile.patterns.filter { $0.status == .mastered } }

    private var nextFocus: RecurringPattern? {
        profile.patterns
            .filter { $0.status != .mastered }
            .max { $0.frequency < $1.frequency }
    }

    private func levelRow(_ lens: Lens) -> some View {
        let level = profile.level(for: lens)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(lensDisplayName(lens))
                Spacer()
                Text("\(level)").foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.subheadline)
            ProgressView(value: Double(level), total: 100).tint(.accentColor)
        }
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
