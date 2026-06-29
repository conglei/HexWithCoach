//
//  PracticeView.swift
//  Voco
//
//  The Practice surface (PR-2) — the drill half of the Coach hub. Replaces the
//  "coming soon" stub in `CoachView` with three sections:
//
//    1. Paste hero — "Practice your own": a card that navigates to a paste
//       screen. The actual paste→segment→shadow flow is PR-3; here the
//       destination is a clearly-marked `PastePracticeView` stub.
//    2. Continue · from your coach — coach-generated drills sourced from
//       `CoachCardEntity` rows with a non-empty `practiceText` (the speakable
//       sentences). Each launches the EXISTING shadowing drill.
//    3. Phrasebook — saved phrasings (`status == .saved`), each launchable into
//       shadowing too.
//
//  Drills reuse the same entry point a Review card's "Say it better" uses:
//  `ShadowingView(target:onComplete:)` in a `.fullScreenCover`. We do NOT
//  reimplement shadowing, scoring, or the paste ingest (PR-3).
//

import VocoCore
import SwiftData
import SwiftUI

struct PracticeView: View {
    /// Coach-generated drills: cards that carry a speakable `practiceText`. Only
    /// improvement cards still in the feed (`new`) — saved ones surface under the
    /// Phrasebook section below so a drill never appears twice.
    @Query(
        filter: #Predicate<CoachCardEntity> {
            $0.practiceText != nil && $0.practiceText != "" && $0.statusRaw == "new"
        },
        sort: \CoachCardEntity.createdAt, order: .reverse
    )
    private var coachDrills: [CoachCardEntity]

    /// Saved phrasings (RC-5). Promoted out of the hidden bookmark into a real
    /// drill list here.
    @Query(
        filter: #Predicate<CoachCardEntity> { $0.statusRaw == "saved" },
        sort: \CoachCardEntity.createdAt, order: .reverse
    )
    private var phrasebook: [CoachCardEntity]

    /// Shared streak/progress, mirroring the Review feed's header.
    @State private var progress = CoachProgress()

    /// The target currently being shadowed (drives the full-screen drill cover).
    /// A non-nil value presents `ShadowingView` with that phrase.
    @State private var activeTarget: ShadowTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                streakHeader
                pasteHero
                coachSection
                phrasebookSection
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .fullScreenCover(item: $activeTarget) { target in
            // Reuse the exact shadowing entry point Review's "Say it better" uses.
            ShadowingView(target: target.text) { progress.recordReview() }
        }
    }

    // MARK: - Streak header

    private var streakHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(progress.streak.current > 0 ? AnyShapeStyle(HexTheme.gradient) : AnyShapeStyle(Color.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(streakText).font(.subheadline.weight(.semibold))
                Text(streakSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .hexCard()
    }

    private var streakText: String {
        let n = progress.streak.current
        return n == 0 ? "Start your streak" : "\(n)-day streak"
    }

    private var streakSubtitle: String {
        progress.streak.best > progress.streak.current
            ? "Best \(progress.streak.best) days · keep practicing"
            : "Practice a drill to keep it going"
    }

    // MARK: - 1. Paste hero

    private var pasteHero: some View {
        NavigationLink {
            PastePracticeView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title2)
                        .foregroundStyle(HexTheme.gradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice your own")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Paste a script, speech, or phrase…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Text("Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(HexTheme.gradient, in: .rect(cornerRadius: 12))
            }
            .hexCard(padding: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Continue · from your coach

    @ViewBuilder
    private var coachSection: some View {
        if !coachDrills.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Continue", subtitle: "from your coach")
                VStack(spacing: 0) {
                    ForEach(Array(coachDrills.enumerated()), id: \.element.id) { index, card in
                        drillRow(
                            title: drillTitle(for: card),
                            subtitle: lensLabel(card.lens),
                            phrase: practiceTarget(for: card)
                        )
                        if index < coachDrills.count - 1 { Divider() }
                    }
                }
                .hexCard(padding: 0)
            }
        }
    }

    // MARK: - 3. Phrasebook

    @ViewBuilder
    private var phrasebookSection: some View {
        if !phrasebook.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Phrasebook", subtitle: "saved phrasings")
                VStack(spacing: 0) {
                    ForEach(Array(phrasebook.enumerated()), id: \.element.id) { index, card in
                        drillRow(
                            title: drillTitle(for: card),
                            subtitle: lensLabel(card.lens),
                            phrase: practiceTarget(for: card)
                        )
                        if index < phrasebook.count - 1 { Divider() }
                    }
                }
                .hexCard(padding: 0)
            }
        }
    }

    // MARK: - Shared row

    /// A single drill: the rule/summary + a play button that launches shadowing
    /// with `phrase`. Disabled (no play) when there's no speakable phrase.
    @ViewBuilder
    private func drillRow(title: String, subtitle: String, phrase: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !phrase.isEmpty {
                Button {
                    activeTarget = ShadowTarget(text: phrase)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(HexTheme.gradient)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Practice this phrase")
            }
        }
        .padding(16)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.title3.weight(.bold))
            Text("· \(subtitle)").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    /// A real, speakable sentence for shadowing — the practice text when present,
    /// else the displayed rewrite (older cards / non-pronunciation lenses). Mirrors
    /// `CoachCardView.practiceTarget` in ReviewView.
    private func practiceTarget(for card: CoachCardEntity) -> String {
        if let practice = card.practiceText, !practice.isEmpty { return practice }
        return card.nativeRewrite ?? ""
    }

    /// The line shown on a drill row: the natural rewrite when there is one, else
    /// the card's title/summary.
    private func drillTitle(for card: CoachCardEntity) -> String {
        if let better = card.nativeRewrite, !better.isEmpty { return better }
        return card.title
    }

    /// Lens → human label, mirroring `CoachCardView.lensLabel`.
    private func lensLabel(_ lens: Lens) -> String {
        switch lens {
        case .grammar: "Grammar"
        case .lexis: "Word choice"
        case .discourse: "Clarity"
        case .pronunciation: "Pronunciation"
        case .prosody: "Fluency"
        }
    }
}

/// Identifiable wrapper so a target phrase can drive a `.fullScreenCover(item:)`.
private struct ShadowTarget: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Paste destination (PR-3 plugs in here)

/// PLACEHOLDER destination for the paste hero. PR-3 replaces this with the real
/// paste → segment → shadow flow (building on `PracticeStore.pasted` /
/// `PracticeItem.segments`). For PR-2 it's a minimal `TextEditor` + a disabled,
/// clearly-marked "coming soon" Start so the entry point and navigation exist.
struct PastePracticeView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a script, speech, or phrase you want to practice. We'll break it into speakable lines and drill them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Paste or type here…")
                                .foregroundStyle(.tertiary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }

                // Intentionally disabled for PR-2 — PR-3 wires the ingest.
                Button {
                    // PR-3: segment `text` → PracticeItem → present ShadowingView.
                } label: {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HexGradientButtonStyle())
                .disabled(true)

                Label("Custom practice is coming soon.", systemImage: "hammer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Practice your own")
        .navigationBarTitleDisplayMode(.inline)
    }
}
