//
//  ReviewView.swift
//  HexIOS
//
//  The Review tab (RC-3) — the hero surface: a feed of "say it better" cards
//  curated from your real speech, styled with HexTheme. Keyless, it shows the
//  activation shell baited with the live captured-backlog count.
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

    var body: some View {
        NavigationStack {
            Group {
                if !preferences.isReady {
                    activationShell
                } else if cards.isEmpty {
                    VStack(spacing: 0) { progressHeader.padding(16); caughtUp }
                } else {
                    feed
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review")
            .toolbar {
                if preferences.isReady {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { PhrasebookView() } label: { Image(systemName: "bookmark") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if coach.isAnalyzing {
                            ProgressView()
                        } else if backlogCount > 0 {
                            Button { Task { await coach.analyzeBacklog() } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
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
        ContentUnavailableView {
            Label("All caught up", systemImage: "checkmark.circle")
        } description: {
            Text(backlogCount > 0
                 ? "\(backlogCount) new dictation\(backlogCount == 1 ? "" : "s") to review."
                 : "New coaching appears here as you dictate.")
        } actions: {
            if backlogCount > 0 {
                Button("Review now") { Task { await coach.analyzeBacklog() } }
                    .buttonStyle(HexGradientButtonStyle(compact: true))
            }
        }
    }

    private var activationShell: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(HexTheme.gradient)
                .frame(width: 72, height: 72)
                .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 4) {
                Text("\(backlogCount)").font(.system(size: 52, weight: .bold))
                Text("moments captured this week")
                    .font(.callout).foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("See how to say it better").font(.headline)
                    Text("Connect an AI key and Hex turns this week's real speech into a few natural-sounding upgrades.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button { selectedTab = .settings } label: { Text("Connect a key") }
                    .buttonStyle(HexGradientButtonStyle())
                Button("How coaching works") { showHowItWorks = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HexTheme.gradientColors[0])
            }
            .hexCard(padding: 20)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Label("Captured on-device · nothing analyzed until you connect", systemImage: "lock.fill")
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
                    Text("Capture stays on this device. Analysis only happens when you connect your own AI key, and you can go incognito or stop anytime.")
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
            header

            if card.kind == .win {
                Text("“\(card.originalSpan ?? card.title)”")
                    .font(.body)
                if !card.detail.isEmpty {
                    Text(card.detail).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                if let said = card.originalSpan {
                    Text("“\(said)”").font(.body).foregroundStyle(.primary)
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

            actions
        }
        .hexCard()
        .fullScreenCover(isPresented: $showShadow) {
            ShadowingView(target: card.nativeRewrite ?? "") { progress.recordReview() }
        }
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
            if card.kind == .improvement, let rewrite = card.nativeRewrite, !rewrite.isEmpty {
                Button { showShadow = true } label: {
                    Label("Say it better", systemImage: "mic.fill")
                }
                .buttonStyle(HexGradientButtonStyle(compact: true))
            }
            Spacer()
            if card.kind == .improvement {
                iconButton("bookmark") { setStatus(.saved) }
            }
            if transcript?.audioFilename != nil, let transcript {
                NavigationLink { TranscriptDetailView(entry: transcript) } label: {
                    Image(systemName: "play.fill")
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
