//
//  ReviewView.swift
//  HexIOS
//
//  The Review tab (RC-3) — the hero surface: a feed of learnable-moment cards
//  curated from your real speech. Monochrome + a single iOS-blue accent. When the
//  Coach is off / keyless, it shows the activation shell baited with the live
//  captured-backlog count, so the value is obvious before you connect a key.
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

    private var cards: [CoachCardEntity] { allCards.filter { $0.status == .new } }
    private var backlogCount: Int { transcripts.filter { $0.coachAnalyzedAt == nil }.count }

    var body: some View {
        NavigationStack {
            Group {
                if !preferences.isReady {
                    activationShell
                } else {
                    VStack(spacing: 0) {
                        progressHeader
                        if cards.isEmpty { caughtUp } else { feed }
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                if preferences.isReady {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { PhrasebookView() } label: {
                            Image(systemName: "bookmark")
                        }
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
            .task(id: preferences.isReady) {
                // Instant first payoff: when ready with a backlog and nothing shown,
                // analyze automatically.
                if preferences.isReady, cards.isEmpty, backlogCount > 0 {
                    await coach.analyzeBacklog()
                }
            }
        }
    }

    // MARK: - Progress header (RC-6)

    private var progressHeader: some View {
        NavigationLink {
            ProgressDigestView(progress: progress)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text(streakText).font(.subheadline.weight(.medium))
                if progress.streak.best > progress.streak.current {
                    Text("· best \(progress.streak.best)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var streakText: String {
        let n = progress.streak.current
        return n == 0 ? "Start your streak" : "\(n)-day streak"
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
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
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var activationShell: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text(backlogCount > 0 ? "\(backlogCount) moments captured" : "Coaching, from your own speech")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Hex turns the English you already speak all day into a few real, natural-sounding tips. Connect your own Gemini key to unlock it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Button { selectedTab = .settings } label: {
                Text("Connect a key").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Text("Capture stays on this device until you connect a key. You choose what's excluded.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
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
        VStack(alignment: .leading, spacing: 10) {
            header

            if card.kind == .win {
                Text(card.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if let said = card.originalSpan {
                    rephraseRow(label: "You said", text: said, accent: false)
                }
                if let better = card.nativeRewrite {
                    rephraseRow(label: "More natural", text: better, accent: true)
                }
                if !card.detail.isEmpty {
                    Text(card.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if card.kind == .improvement, let rewrite = card.nativeRewrite, !rewrite.isEmpty {
                Button { showShadow = true } label: {
                    Label("Say it better", systemImage: "waveform.badge.mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            actions
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fullScreenCover(isPresented: $showShadow) {
            ShadowingView(target: card.nativeRewrite ?? "") { progress.recordReview() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: card.kind == .win ? "checkmark.seal.fill" : lensIcon)
                .foregroundStyle(card.kind == .win ? Color.accentColor : .secondary)
            Text(card.kind == .win ? "Win" : lensLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if let note = card.recurrenceNote {
                Text(note).font(.caption2).foregroundStyle(Color.accentColor)
            }
        }
    }

    private func rephraseRow(label: String, text: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(text)
                .font(.body)
                .foregroundStyle(accent ? Color.accentColor : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 18) {
            if transcript?.audioFilename != nil, let transcript {
                NavigationLink {
                    TranscriptDetailView(entry: transcript)
                } label: {
                    Label("Context", systemImage: "waveform")
                }
            }
            if card.kind == .improvement {
                Button { setStatus(.saved) } label: { Label("Save", systemImage: "bookmark") }
            }
            Spacer()
            Button { setStatus(.dismissed) } label: { Image(systemName: "hand.thumbsdown") }
                .tint(.secondary)
            Button { setStatus(.done) } label: { Label("Got it", systemImage: "checkmark") }
        }
        .font(.footnote)
        .buttonStyle(.borderless)
        .padding(.top, 2)
    }

    private func setStatus(_ status: CoachCardStatus) {
        card.status = status
        try? modelContext.save()
        // Acting on a card counts toward today's streak (RC-6).
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

    private var lensIcon: String {
        switch card.lens {
        case .grammar: "text.badge.checkmark"
        case .lexis: "character.book.closed"
        case .discourse: "scissors"
        case .pronunciation: "waveform"
        case .prosody: "speedometer"
        }
    }
}
