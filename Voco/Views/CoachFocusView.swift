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
            // shows up. CF-fix: `reload` recomputes the (pure, cheap) surface + stats
            // every time, but the qualitative recap is read from the per-week
            // persistent cache — so a normal tab glance triggers NO LLM call and the
            // wording stays stable. The recap regenerates only when the week rolls
            // over or the grounded inputs change.
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
                    onScored: { persistAttempt(for: drill, score: $0.score) },
                    onComplete: { progress.recordReview() }
                )
            case .shadow:
                ShadowingView(
                    target: drill.content.target,
                    onScored: { persistAttempt(for: drill, score: $0.score) },
                    onComplete: { progress.recordReview() }
                )
            }
        }
    }

    /// Persist one `PracticeAttempt` for a focus-launched drill, tagged (CF-3) with
    /// the focus area's `lens` + `patternKey`. This is what closes the loop: the
    /// attempt becomes attributable to the very pattern the focus targets, so the
    /// practice→frequency-drop signal can later show that drilling it moved the needle.
    /// The `PracticeItem` is created lazily with `.coachInsight` origin pointing back
    /// at the focus's pattern.
    private func persistAttempt(for drill: ActiveFocusDrill, score: Double) {
        let item = PracticeStore.coachInsight(
            drill.content.target,
            segments: SentenceSegmenter.segments(from: drill.content.target),
            sourceID: drill.patternID,
            kind: drill.kind,
            patternKey: drill.patternKey,
            lens: drill.lens,
            title: drill.content.title
        )
        modelContext.insert(item)
        let attempt = PracticeAttempt(perSegmentScores: [score], gopDelta: nil, item: item)
        modelContext.insert(attempt)
        try? modelContext.save()
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if coach.isAnalyzing { reviewingBanner }
                summarySection
                practiceStrip
                skillMapSection
                focusSection
                browseAllSection
            }
            .padding(16)
        }
    }

    // MARK: - 1. Weekly summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(HexTheme.gradient)
                Text("This week")
                    .font(.headline)
                Spacer()
            }

            // PART 1 — the deterministic stats block. Every number here is computed
            // by us; the LLM never produces or restates one.
            if let stats = model?.stats, stats.hasData {
                statsBlock(stats)
            }

            // PART 2 — the qualitative, number-free LLM coaching recap (cached per
            // week). Visually separated from the stats so the two parts never blur.
            Divider()
            if let summary = model?.summary {
                Text(summary.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Putting together your weekly recap…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .redacted(reason: model?.isGeneratingSummary == true ? .placeholder : [])
            }
        }
        .hexCard(padding: 18)
    }

    /// The deterministic metrics row — minutes spoken, notes logged, fillers/min.
    /// Honest, computed numbers; kept entirely separate from the recap prose.
    private func statsBlock(_ stats: CoachStats) -> some View {
        HStack(alignment: .top, spacing: 0) {
            statMetric(value: "\(stats.minutesSpoken)", unit: stats.minutesSpoken == 1 ? "minute" : "minutes", label: "spoken")
            statDivider
            statMetric(value: "\(stats.noteCount)", unit: stats.noteCount == 1 ? "note" : "notes", label: "logged")
            if let fpm = stats.fillersPerMinute {
                statDivider
                statMetric(value: String(format: "%.1f", fpm), unit: "/min", label: "fillers")
            }
        }
    }

    private func statMetric(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(HexTheme.gradient)
                Text(unit)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 32)
    }

    // MARK: - 1b. "Today / this week you practiced" strip (CF-3)

    /// Visible accumulation: reps this week grouped by lens, each with the
    /// growth-framed improvement delta. Frames practice as polish — "more natural",
    /// "more on-target" — never "errors fixed". Hides entirely when nothing was
    /// practiced this week, so it never shows a hollow zero.
    @ViewBuilder
    private var practiceStrip: some View {
        if let summary = model?.practice, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("YOU PRACTICED")
                VStack(alignment: .leading, spacing: 12) {
                    // Headline: reps today + this week.
                    HStack(spacing: 8) {
                        Image(systemName: "figure.mind.and.body")
                            .foregroundStyle(HexTheme.gradient)
                        Text(practiceHeadline(summary))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    // Per-lens rows: reps + the refinement delta.
                    ForEach(summary.byLens) { row in
                        Divider()
                        practiceLensRow(row)
                    }
                }
                .hexCard(padding: 16)
            }
        }
    }

    private func practiceHeadline(_ s: PracticeSummary) -> String {
        let week = "\(s.repsThisWeek) rep\(s.repsThisWeek == 1 ? "" : "s") this week"
        if s.repsToday > 0 {
            return "\(s.repsToday) today · \(week)"
        }
        return week
    }

    private func practiceLensRow(_ row: LensPracticeReps) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lensDisplayName(row.lens)).font(.subheadline.weight(.medium))
                Text("\(row.reps) rep\(row.reps == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Refinement delta — only shown when there's enough to compare and it's
            // a genuine gain (growth-only; a dip never reads as punishment).
            if let delta = row.scoreDelta, delta >= 0.02 {
                Label("\(Int((delta * 100).rounded()))% more natural", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HexTheme.gradientColors[0])
            } else if let gop = row.gopDelta, gop > 0 {
                Label("clearer", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HexTheme.gradientColors[0])
            } else {
                Text("keeping it sharp")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 1c. Practice → frequency-drop card (CF-3, the payoff)

    /// The single most motivating thing a coaching app can show: proof the practice
    /// worked. Only rendered when the honesty guard cleared (`model.heroTrend` is
    /// non-nil), so it never declares victory on noise. Framed as dropping below an
    /// earlier baseline — refinement, not "errors fixed".
    @ViewBuilder
    private func frequencyTrendCard(_ trend: FrequencyTrend) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(HexTheme.gradient)
                Text("It's working")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text("You practiced this \(trend.totalReps)× and it's now showing up about \(trend.recentOccurrences)× a day — down from \(trend.baselineOccurrences)× before you started.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            trendSparkline(trend)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous))
    }

    /// A tiny inline bar chart of per-period occurrences, with practiced periods
    /// marked — the "occurrences over time with practice overlaid" the issue asks for.
    private func trendSparkline(_ trend: FrequencyTrend) -> some View {
        let buckets = trend.buckets
        let maxOcc = max(1, buckets.map(\.occurrences).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(buckets) { bucket in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(bucket.practiceReps > 0 ? AnyShapeStyle(HexTheme.gradient) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                        .frame(width: 6, height: max(3, CGFloat(bucket.occurrences) / CGFloat(maxOcc) * 36))
                    // Tiny dot under periods where the user practiced.
                    Circle()
                        .fill(bucket.practiceReps > 0 ? AnyShapeStyle(HexTheme.gradient) : AnyShapeStyle(Color.clear))
                        .frame(width: 3, height: 3)
                }
            }
        }
        .frame(height: 44, alignment: .bottom)
        .accessibilityLabel("Occurrences over time; highlighted bars are days you practiced.")
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
        // CF-fix: the ungrounded numeric "level" is gone. The row shows the lens name
        // and an honest, evidence-grounded TREND ("needs work" when a pattern is
        // actively recurring; "improving" on a win; else "steady").
        HStack(spacing: 8) {
            Text(lensDisplayName(skill.lens)).font(.subheadline.weight(.medium))
            Spacer()
            trendBadge(skill.trend)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// A trend arrow + word for a lens (or focus). Grounded in real pattern signal.
    private func trendBadge(_ trend: CoachLensTrend) -> some View {
        Label(trend.label, systemImage: trend.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(trendColor(trend))
    }

    @ViewBuilder
    private func trendArrow(_ trend: CoachLensTrend) -> some View {
        Image(systemName: trend.systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(trendColor(trend))
    }

    private func trendColor(_ trend: CoachLensTrend) -> Color {
        switch trend {
        case .improving: HexTheme.gradientColors[0]
        case .steady: .secondary
        case .needsWork: HexTheme.gradientColors[0]
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

                // CF-3 payoff: when practicing this focus genuinely reduced its
                // frequency (honesty guard passed), prove it right under the card.
                if let trend = model?.heroTrend, trend.lens == hero.lens, trend.patternKey == hero.key {
                    frequencyTrendCard(trend)
                }

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
        activeDrill = ActiveFocusDrill(
            kind: kind, content: content,
            lens: focus.lens, patternKey: focus.key, patternID: pattern?.id ?? UUID()
        )
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
/// Carries the focus area's `(lens, patternKey)` (CF-3) so the recorded attempt is
/// attributable to the pattern it targets, closing the practice→frequency-drop loop.
private struct ActiveFocusDrill: Identifiable {
    let id = UUID()
    let kind: PracticeKind
    let content: PracticeDrillContent
    let lens: Lens
    let patternKey: String
    /// The profile pattern's id (the drill's `sourceID`), so the `PracticeItem` links
    /// back to a stable source. A fresh UUID when no profile pattern backs the focus.
    let patternID: UUID
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
