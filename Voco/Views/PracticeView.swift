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

// MARK: - Paste destination (PR-3)

/// "Practice your own" (PR-3): paste/type arbitrary text → segment it into
/// speakable sentences → create a `.pasted` `PracticeItem` → drive the EXISTING
/// shadowing drill (`ShadowingView`) over each segment in sequence → save a
/// `PracticeAttempt` with the per-segment scores. Pasted text is just a new
/// *source* for the shadowing engine — no new scoring here.
///
/// Nothing touches `TranscriptStore` / History: this is entirely `PracticeItem` /
/// `PracticeAttempt` (PR-1 models).
struct PastePracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    /// The live segment preview, recomputed as the learner edits.
    @State private var segments: [String] = []
    /// The persisted item + its segments, set when a session starts. Drives the
    /// full-screen shadowing session over the segments.
    @State private var session: PasteSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a script, speech, or phrase you want to practice. We'll break it into speakable lines and drill them one at a time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .frame(minHeight: 180)
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
                    .onChange(of: text) { _, newValue in
                        segments = SentenceSegmenter.segments(from: newValue)
                    }

                segmentPreview

                Button { startSession() } label: {
                    Text(segments.count <= 1 ? "Start" : "Practice \(segments.count) lines")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HexGradientButtonStyle())
                .disabled(segments.isEmpty)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Practice your own")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $session) { session in
            PasteShadowingSession(item: session.item, segments: session.segments)
        }
    }

    // MARK: - Segment preview

    @ViewBuilder
    private var segmentPreview: some View {
        if !segments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(segments.count) line\(segments.count == 1 ? "" : "s") to practice")
                    .font(.caption.weight(.bold)).tracking(0.5)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, sentence in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(HexTheme.gradient)
                                .frame(minWidth: 18, alignment: .trailing)
                            Text(sentence)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 4)
                        if index < segments.count - 1 { Divider() }
                    }
                }
                .hexCard(padding: 12)
            }
        }
    }

    // MARK: - Start

    /// Create + persist a `.pasted` `PracticeItem` from the current text/segments,
    /// then present the shadowing session over those segments.
    private func startSession() {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segments.isEmpty else { return }
        let item = PracticeStore.pasted(sourceText, segments: segments)
        modelContext.insert(item)
        try? modelContext.save()
        session = PasteSession(item: item, segments: segments)
    }
}

/// Identifiable wrapper so the persisted item + its frozen segment list can drive
/// the session's `.fullScreenCover(item:)`.
private struct PasteSession: Identifiable {
    let id = UUID()
    let item: PracticeItem
    let segments: [String]
}

// MARK: - Multi-segment shadowing session

/// Drives the EXISTING `ShadowingView` over each segment in sequence: present the
/// drill for segment N, advance on its completion, collect the per-segment score,
/// and at the end show a brief summary and save a `PracticeAttempt` onto the item.
/// Reuses `ShadowingView`/`ShadowingModel` for all TTS/ASR/GOP — this is only the
/// iterator + summary + persistence.
private struct PasteShadowingSession: View {
    let item: PracticeItem
    let segments: [String]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Pure advancement + payload state machine (testable in VocoCore). The view
    /// only renders the current segment / summary and persists the attempt.
    @State private var state: PasteSessionState
    @State private var saved = false

    init(item: PracticeItem, segments: [String]) {
        self.item = item
        self.segments = segments
        _state = State(initialValue: PasteSessionState(segments: segments))
    }

    var body: some View {
        Group {
            if let segment = state.currentSegment {
                // A fresh ShadowingView per segment (re-init resets its model).
                // dismissOnComplete:false — this view is embedded directly in the
                // session's cover with NO presentation boundary, so the per-segment
                // drill must NOT own the cover's dismiss; advancement is driven
                // purely via onScored/onComplete and the session owns dismissal.
                ShadowingView(
                    target: segment,
                    dismissOnComplete: false,
                    onScored: { result in
                        state.recordCurrent(score: result.score, gopDelta: result.gopDelta)
                    },
                    onComplete: {}
                )
                .id(state.index)   // force a new ShadowingModel for each segment
            } else {
                summary
            }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(HexTheme.gradient)
                Text("Session complete")
                    .font(.title2.weight(.bold))
                Text(overallText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { i, sentence in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(sentence)
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text(scorePercent(at: i))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(scoreColor(at: i))
                        }
                        .padding(.vertical, 10).padding(.horizontal, 4)
                        if i < segments.count - 1 { Divider() }
                    }
                }
                .hexCard(padding: 12)

                Button("Done") { dismiss() }
                    .buttonStyle(HexGradientButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: saveAttempt)
    }

    private var overallText: String {
        let scores = state.scores
        guard !scores.isEmpty else { return "Practiced \(segments.count) line\(segments.count == 1 ? "" : "s")." }
        let avg = state.averageScore
        return "Overall \(Int((avg * 100).rounded()))% match across \(scores.count) line\(scores.count == 1 ? "" : "s")."
    }

    private func scorePercent(at index: Int) -> String {
        guard index < state.scores.count else { return "—" }
        return "\(Int((state.scores[index] * 100).rounded()))%"
    }

    private func scoreColor(at index: Int) -> Color {
        guard index < state.scores.count else { return .secondary }
        return state.scores[index] >= ShadowingScorer.matchThreshold ? .green : .orange
    }

    /// Save one `PracticeAttempt` for the whole session onto the item, using the
    /// state machine's payload (per-segment scores + averaged GOP delta).
    /// Idempotent — `.onAppear` can fire more than once.
    private func saveAttempt() {
        guard !saved else { return }
        saved = true
        let payload = state.attemptPayload
        let attempt = PracticeAttempt(
            perSegmentScores: payload.perSegmentScores,
            gopDelta: payload.gopDelta,
            item: item
        )
        modelContext.insert(attempt)
        try? modelContext.save()
    }
}
