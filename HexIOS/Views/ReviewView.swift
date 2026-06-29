//
//  ReviewView.swift
//  HexIOS
//
//  The Review tab (RC-3) — the hero surface: a feed of "say it better" cards
//  curated from your real speech, styled with HexTheme.
//
//  Keyless-first (CI-5 / ADR-0002): the objective lane (pronunciation + fluency)
//  authors real cards with zero LLM, so the feed is shown whether or not a BYOK
//  key is present. A key is no longer a gate — it's a non-blocking upsell that
//  unlocks the meaning lenses (grammar / word choice / clarity), the intonation
//  lens, and richer LLM-authored teaching.
//

import HexCore
import SwiftData
import SwiftUI

struct ReviewView: View {
    let coach: CoachService
    let preferences: CoachPreferences
    @Binding var selectedTab: AppTab

    @Query(sort: \CoachCardEntity.createdAt, order: .reverse) private var allCards: [CoachCardEntity]
    @Query private var transcripts: [TranscriptEntry]
    @State private var progress = CoachProgress()
    @State private var showHowItWorks = false

    private var cards: [CoachCardEntity] { allCards.filter { $0.status == .new } }
    private var backlogCount: Int { transcripts.filter { $0.coachAnalyzedAt == nil }.count }

    private var gatingInputs: ReviewFeedGating.Inputs {
        ReviewFeedGating.Inputs(
            hasCards: !cards.isEmpty,
            hasKey: preferences.isReady,
            hasNotes: !transcripts.isEmpty
        )
    }

    private var showsUpsell: Bool { ReviewFeedGating.showsKeyUpsell(gatingInputs) }

    var body: some View {
        NavigationStack {
            Group {
                switch ReviewFeedGating.feedState(gatingInputs) {
                case .feed:
                    feed
                case .caughtUp:
                    VStack(spacing: 0) { progressHeader.padding(16); caughtUp }
                case .onboarding:
                    onboarding
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review")
            .safeAreaInset(edge: .top) {
                if coach.isAnalyzing { reviewingBanner }
            }
            .animation(.easeInOut(duration: 0.2), value: coach.isAnalyzing)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { PhrasebookView() } label: { Image(systemName: "bookmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // The running state lives in the banner now; the toolbar only
                    // offers the manual refresh when a keyed user has a backlog.
                    // (Keyless objective analysis runs per-note; CI-7 owns automation.)
                    if preferences.isReady, !coach.isAnalyzing, backlogCount > 0 {
                        Button { Task { await coach.analyzeBacklog() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(isPresented: $showHowItWorks) { howItWorks }
            .task(id: preferences.isReady) {
                if preferences.isReady, cards.isEmpty, backlogCount > 0 {
                    await coach.analyzeBacklog()
                }
            }
        }
    }

    // MARK: - Streak header (RC-6)

    private var progressHeader: some View {
        NavigationLink {
            ProgressDigestView(progress: progress)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(HexTheme.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(streakText).font(.subheadline.weight(.semibold))
                    Text(trendText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var streakText: String {
        let n = progress.streak.current
        return n == 0 ? "Start your streak" : "\(n)-day streak"
    }

    private var trendText: String {
        progress.streak.best > progress.streak.current
            ? "Best \(progress.streak.best) days · keep it going"
            : "Reviewing your real speech"
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                progressHeader
                if showsUpsell {
                    KeyUpsellBanner { selectedTab = .settings }
                }
                Text("TODAY")
                    .font(.caption.weight(.semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                ForEach(cards) { card in
                    CoachCardView(card: card, transcript: transcript(for: card), progress: progress)
                }
            }
            .padding(16)
        }
    }

    private func transcript(for card: CoachCardEntity) -> TranscriptEntry? {
        guard let id = card.transcriptID else { return nil }
        return transcripts.first { $0.id == id }
    }

    // MARK: - States

    private var caughtUp: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsUpsell {
                    KeyUpsellBanner { selectedTab = .settings }
                }
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.circle")
                } description: {
                    Text(backlogCount > 0
                         ? "\(backlogCount) new dictation\(backlogCount == 1 ? "" : "s") to review."
                         : "New coaching appears here as you dictate.")
                } actions: {
                    if preferences.isReady, backlogCount > 0 {
                        Button { Task { await coach.analyzeBacklog() } } label: {
                            if coach.isAnalyzing {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Reviewing…")
                                }
                            } else {
                                Text("Review now")
                            }
                        }
                        .buttonStyle(HexGradientButtonStyle(compact: true))
                        .disabled(coach.isAnalyzing)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// A clear, pinned indicator while a review run is in progress — more
    /// informative than a bare toolbar spinner, and visible in every state.
    private var reviewingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Reviewing your new dictations…")
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(12)
        .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// First-run state: nothing dictated yet. NOT the old "connect a key" wall —
    /// coaching is free and on-device; you just need to speak first.
    private var onboarding: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(HexTheme.gradient)
                .frame(width: 72, height: 72)
                .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("Your coaching starts here").font(.headline)
                    Text("Dictate with Hex and your pronunciation and fluency get coached automatically — free, on-device. Your cards show up here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("How coaching works") { showHowItWorks = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HexTheme.gradientColors[0])
            }
            .hexCard(padding: 20)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if showsUpsell {
                KeyUpsellBanner { selectedTab = .settings }
                    .padding(.horizontal, 8)
            }

            Label("Pronunciation & fluency analyzed on-device · the cloud is opt-in", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var howItWorks: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Hex listens to the English you already speak all day — across your apps — and turns the most learnable moments into a few real, natural-sounding upgrades.")
                    Text("Pronunciation and fluency coaching run entirely on this device, for free. Add your own AI key to also unlock grammar, word-choice, clarity, and intonation feedback — the cloud is always opt-in, and you can go incognito or stop anytime.")
                    Text("Each card shows what you said, a more natural way to say it, and why. Tap “Say it better” to hear it and practice.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(20)
            }
            .navigationTitle("How coaching works")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Card

private struct CoachCardView: View {
    let card: CoachCardEntity
    let transcript: TranscriptEntry?
    let progress: CoachProgress

    @Environment(\.modelContext) private var modelContext
    @State private var showShadow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardText
            actions
        }
        .hexCard()
        .fullScreenCover(isPresented: $showShadow) {
            ShadowingView(target: practiceTarget) { progress.recordReview() }
        }
    }

    /// The textual region of the card. When the card came from a real note it taps
    /// through to that note (with the flagged span highlighted in context);
    /// otherwise it's just plain text.
    @ViewBuilder
    private var cardText: some View {
        if let transcript {
            NavigationLink {
                TranscriptDetailView(entry: transcript, highlightSpan: card.originalSpan)
            } label: {
                cardTextBody
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        } else {
            cardTextBody
        }
    }

    private var cardTextBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if card.kind == .win {
                Text("“\(card.originalSpan ?? card.title)”")
                    .font(.body)
                if !card.detail.isEmpty {
                    Text(card.detail).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                if !(card.originalSpan ?? "").isEmpty || !(card.context ?? "").isEmpty {
                    Text(contextAttributed).font(.body)
                }
                if let better = card.nativeRewrite {
                    HStack(spacing: 4) {
                        Image(systemName: rewriteIsPhonetic ? "waveform" : "arrow.down")
                        Text(rewriteIsPhonetic ? "SAY IT LIKE" : "MORE NATURAL").tracking(0.5)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HexTheme.gradientColors[0])
                    Text("“\(better)”")
                        .font(.body.weight(.medium))
                }
                if !card.detail.isEmpty {
                    Text(card.detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The flagged span shown inside its surrounding sentence, with the user's exact
    /// words emphasized so the quote reads in context. Falls back to the bare span
    /// for older cards that have no stored context.
    private var contextAttributed: AttributedString {
        let span = card.originalSpan ?? ""
        let context = card.context ?? ""
        if context.isEmpty {
            var plain = AttributedString("“\(span)”")
            plain.foregroundColor = .primary
            return plain
        }
        var attributed = AttributedString("“\(context)”")
        attributed.foregroundColor = .secondary
        if !span.isEmpty, let range = attributed.range(of: span, options: .caseInsensitive) {
            attributed[range].foregroundColor = .primary
            attributed[range].font = .body.weight(.semibold)
        }
        return attributed
    }

    /// A real, speakable sentence for shadowing — the practice text when present,
    /// else the displayed rewrite (older cards / non-pronunciation lenses).
    private var practiceTarget: String {
        if let practice = card.practiceText, !practice.isEmpty { return practice }
        return card.nativeRewrite ?? ""
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
            Spacer()
            lensBadge
        }
    }

    private var sourceLabel: String {
        let kind = transcript?.kind.label ?? "Dictation"
        let time = (transcript?.date ?? card.createdAt).formatted(date: .omitted, time: .shortened)
        return "\(kind) · \(time)"
    }

    @ViewBuilder
    private var lensBadge: some View {
        if card.kind == .win {
            Label("Nice phrasing", systemImage: "checkmark")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.green)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.green.opacity(0.12), in: .capsule)
        } else {
            Text(lensLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(HexTheme.gradientColors[0])
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(HexTheme.gradientSoft, in: .capsule)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if card.kind == .improvement, !practiceTarget.isEmpty {
                Button { showShadow = true } label: {
                    Label("Say it better", systemImage: "mic.fill")
                }
                .buttonStyle(HexGradientButtonStyle(compact: true))
            }
            Spacer()
            if card.kind == .improvement {
                iconButton("bookmark") { setStatus(.saved) }
            }
            // Always offer a way into the source note (not just when audio exists).
            if let transcript {
                NavigationLink { TranscriptDetailView(entry: transcript, highlightSpan: card.originalSpan) } label: {
                    Image(systemName: "note.text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.plain)
            }
            iconButton("hand.thumbsdown") { setStatus(.dismissed) }
            iconButton("checkmark") { setStatus(.done) }
        }
        .padding(.top, 2)
    }

    private func iconButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func setStatus(_ status: CoachCardStatus) {
        card.status = status
        try? modelContext.save()
        progress.recordReview()
    }

    private var lensLabel: String {
        switch card.lens {
        case .grammar: "Grammar"
        case .lexis: "Word choice"
        case .discourse: "Clarity"
        case .pronunciation: "Pronunciation"
        case .prosody: "Fluency"
        }
    }

    /// Pronunciation/prosody rewrites are a phonetic target ("THINK [θɪŋk]"), not
    /// a reworded sentence — label them so the learner reads them as a sound cue.
    private var rewriteIsPhonetic: Bool {
        card.lens == .pronunciation || card.lens == .prosody
    }
}
