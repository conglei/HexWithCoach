//
//  CoachFocusView.swift
//  Voco
//
//  CF-1 — the de-overwhelmed Coach "Focus" surface. Replaces the flat inbox of
//  per-note `.new` cards (hundreds of items, "really not usable") with what a
//  professional coach actually gives:
//
//    1. Weekly summary — a grounded LLM recap (or structured-template fallback)
//       synthesizing all five lenses, our numbers interpolated. Generated once per
//       rollup and cached by `CoachFocusModel` (never per view).
//    2. Skill map — the five lenses, each a level + trend arrow, tappable → detail.
//    3. One prioritized focus (occasionally up to 3, collapsed) — title + evidence
//       ("9× this week" + an example) + a one-tap Practice that routes to CF-2's
//       matched drill via the focus's lens.
//    4. Browse all findings — the OLD flat list, demoted to depth. Nothing is lost;
//       it just stops being the front door.
//
//  FX-1 lesson honoured: this is a real installed `View`, so its `@Query` /
//  `@Environment(\.modelContext)` bind. The ranking + summary are pure VocoCore;
//  this view only renders the model's output and routes the Practice CTA into the
//  EXISTING drill entry points (ShadowingView / WordSwapView), exactly as
//  PracticeView does.
//

import VocoCore
import SwiftData
import SwiftUI

struct CoachFocusView: View {
    let coach: CoachService
    let preferences: CoachPreferences
    @Binding var selectedTab: AppTab

    @Environment(\.modelContext) private var modelContext

    /// Drives gating: with no notes at all we show the same warm onboarding the old
    /// feed used rather than an empty skill map.
    @Query private var transcripts: [TranscriptEntry]

    @State private var model: CoachFocusModel?
    @State private var progress = CoachProgress()
    @State private var activeDrill: ActiveFocusDrill?
    @State private var showSecondary = false

    var body: some View {
        Group {
            if transcripts.isEmpty {
                onboarding
            } else {
                content
            }
        }
        .background(Color(.systemGroupedBackground))
        .task(id: coach.isAnalyzing) {
            // Build the model lazily (needs the environment's context) and reload
            // whenever an analysis run flips to idle, so a fresh capture's coaching
            // shows up. The summary is generated + cached inside reload.
            if model == nil {
                model = CoachFocusModel(modelContext: modelContext, preferences: preferences)
            }
            if !coach.isAnalyzing { await model?.reload() }
        }
        .fullScreenCover(item: $activeDrill) { drill in
            switch drill.kind {
            case .wordSwap:
                WordSwapView(
                    drill: WordSwapDrill(content: drill.content),
                    onScored: { _ in },
                    onComplete: { progress.recordReview() }
                )
            case .shadow:
                ShadowingView(
                    target: drill.content.target,
                    onScored: { _ in },
                    onComplete: { progress.recordReview() }
                )
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if coach.isAnalyzing { reviewingBanner }
                summarySection
                skillMapSection
                focusSection
                browseAllSection
            }
            .padding(16)
        }
    }

    // MARK: - 1. Weekly summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(HexTheme.gradient)
                Text("This week")
                    .font(.headline)
                Spacer()
                if let summary = model?.summary, summary.source == .template {
                    // Honest about the path: a keyless recap is a leaner template.
                    Text("Recap")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let summary = model?.summary {
                Text(summary.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Placeholder while the (cached-after-first) recap generates.
                Text("Putting together your weekly recap…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .redacted(reason: model?.isGeneratingSummary == true ? .placeholder : [])
            }
        }
        .hexCard(padding: 18)
    }

    // MARK: - 2. Skill map

    private var skillMapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("YOUR SKILLS")
            VStack(spacing: 14) {
                ForEach(model?.surface.skillMap ?? []) { skill in
                    NavigationLink {
                        LensDetailView(lens: skill.lens)
                    } label: {
                        skillRow(skill)
                    }
                    .buttonStyle(.plain)
                }
            }
            .hexCard()
        }
    }

    private func skillRow(_ skill: LensSkill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(lensDisplayName(skill.lens)).font(.subheadline.weight(.medium))
                trendArrow(skill.trend)
                Spacer()
                Text("\(skill.level)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            ProgressView(value: Double(skill.level), total: 100)
                .tint(HexTheme.gradientColors[0])
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func trendArrow(_ trend: ProgressSummary.Trend) -> some View {
        switch trend {
        case .improving:
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(HexTheme.gradientColors[0])
        case .steady:
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        case .new:
            EmptyView()
        }
    }

    // MARK: - 3. Prioritized focus

    @ViewBuilder
    private var focusSection: some View {
        let focuses = model?.surface.focuses ?? []
        if let hero = focuses.first {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("FOCUS NEXT")
                focusCard(hero, isHero: true)

                let secondary = Array(focuses.dropFirst())
                if !secondary.isEmpty {
                    if showSecondary {
                        ForEach(secondary) { focusCard($0, isHero: false) }
                    }
                    Button {
                        withAnimation { showSecondary.toggle() }
                    } label: {
                        Label(
                            showSecondary ? "Hide other focuses" : "\(secondary.count) more to consider",
                            systemImage: showSecondary ? "chevron.up" : "chevron.down"
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } else if !(model?.surface.skillMap.isEmpty ?? true) {
            // No focus cleared the high evidence bar — that's a GOOD state for a
            // fluent user, not an empty one. Say so rather than show nothing.
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("FOCUS NEXT")
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2).foregroundStyle(HexTheme.gradient)
                    Text("Nothing stands out to drill right now — you're polishing at a high level. Keep speaking and new focuses will surface as patterns build up.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .hexCard()
            }
        }
    }

    private func focusCard(_ focus: FocusArea, isHero: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(lensDisplayName(focus.lens))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HexTheme.gradientColors[0])
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(HexTheme.gradientSoft, in: .capsule)
                Spacer()
                trendArrow(focus.trend)
            }
            Text(focus.title.localizedCapitalizedFirst)
                .font(isHero ? .title3.weight(.semibold) : .headline)
                .fixedSize(horizontal: false, vertical: true)
            if !focus.rule.isEmpty {
                Text(focus.rule)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Evidence: the count + a verbatim example from the user's own speech.
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text("\(focus.frequency)× this week")
                if let span = focus.exampleSpan, !span.isEmpty {
                    Text("· “\(span)”").lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    launchPractice(for: focus)
                } label: {
                    Label(focus.practiceKind == .wordSwap ? "Practice word choice" : "Practice", systemImage: "mic.fill")
                }
                .buttonStyle(HexGradientButtonStyle(compact: true))
                Spacer()
                NavigationLink {
                    LensDetailView(lens: focus.lens)
                } label: {
                    Text("See pattern").font(.footnote.weight(.medium))
                }
            }
        }
        .hexCard(padding: 18)
    }

    // MARK: - 4. Browse all (the demoted flat list)

    private var browseAllSection: some View {
        NavigationLink {
            // The OLD flat feed, intact — nothing lost, just demoted from the front
            // door. Embedded so it renders without its own nav stack.
            ReviewView(coach: coach, preferences: preferences, selectedTab: $selectedTab, embedded: true)
                .navigationTitle("All findings")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
                Text("Browse all findings")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Practice routing

    /// Launch CF-2's matched drill for a focus. The focus carries no card, so build
    /// the drill content from the focus + its profile pattern (the example span is
    /// the "before"; the rule frames the rewrite). Lens picks the kind.
    private func launchPractice(for focus: FocusArea) {
        let kind = focus.practiceKind
        let pattern = model?.pattern(for: focus)
        // A speakable target: prefer the example span (the learner's own sentence),
        // else the title. Shadowing reads `target`; word-swap uses originalSpan.
        let span = focus.exampleSpan ?? pattern?.examples.last?.span
        let target = span ?? focus.title
        let content = PracticeDrillContent(
            title: focus.title,
            target: target,
            originalSpan: span,
            nativeRewrite: nil,
            context: pattern?.rule,
            lens: focus.lens
        )
        activeDrill = ActiveFocusDrill(kind: kind, content: content)
    }

    // MARK: - States

    private var reviewingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Reviewing your new dictations…")
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(12)
        .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var onboarding: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(HexTheme.gradient)
                .frame(width: 72, height: 72)
                .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(spacing: 6) {
                Text("Your coaching starts here").font(.headline)
                Text("Dictate with Voco and your speaking gets coached automatically — free, on-device. Your weekly recap and the one thing to polish next will show up here.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .hexCard(padding: 20)
            .padding(.horizontal, 8)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold)).tracking(1)
            .foregroundStyle(.secondary)
    }
}

/// Identifiable wrapper so a focus-launched drill can drive `.fullScreenCover(item:)`.
private struct ActiveFocusDrill: Identifiable {
    let id = UUID()
    let kind: PracticeKind
    let content: PracticeDrillContent
}

// MARK: - Lens detail (drill-down)

/// Tapping a lens (skill map row or "See pattern") lands here: the lens's specific
/// recurring patterns from the profile, with frequency + the learner's own examples.
/// This is the per-lens depth the issue asks for; "browse all findings" remains the
/// full flat list one level up.
struct LensDetailView: View {
    let lens: Lens

    @State private var patterns: [RecurringPattern] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if patterns.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing recurring yet", systemImage: "checkmark.circle")
                    } description: {
                        Text("No repeated patterns in \(lensDisplayName(lens).lowercased()) — keep speaking and any that build up will show here.")
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(patterns) { pattern in
                        patternCard(pattern)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(lensDisplayName(lens))
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
    }

    private func patternCard(_ pattern: RecurringPattern) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pattern.summary.localizedCapitalizedFirst)
                    .font(.headline)
                Spacer()
                statusBadge(pattern.status)
            }
            if !pattern.rule.isEmpty {
                Text(pattern.rule).font(.footnote).foregroundStyle(.secondary)
            }
            if pattern.frequency >= 2 {
                Text("Came up \(pattern.frequency)×").font(.caption).foregroundStyle(.secondary)
            }
            if !pattern.examples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(pattern.examples.suffix(3).enumerated()), id: \.offset) { _, ex in
                        Text("“\(ex.span)”")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .hexCard()
    }

    @ViewBuilder
    private func statusBadge(_ status: PatternStatus) -> some View {
        switch status {
        case .mastered:
            Label("mastered", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.green)
        case .improving:
            Label("improving", systemImage: "arrow.up.right")
                .font(.caption2.weight(.semibold)).foregroundStyle(HexTheme.gradientColors[0])
        case .active:
            EmptyView()
        }
    }

    private func reload() {
        // Single source of truth (`CoachPaths`) — same path the engine writes and
        // the seed seeds, on both the entitled and the nil-container branch.
        let profile = LearnerProfileStore(url: CoachPaths.profileURL()).load()
        patterns = profile.patterns
            .filter { $0.lens == lens }
            .sorted { $0.frequency > $1.frequency }
    }
}

private extension String {
    /// Capitalize only the first character (titles read better than fully cased).
    var localizedCapitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
