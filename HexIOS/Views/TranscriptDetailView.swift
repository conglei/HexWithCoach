//
//  TranscriptDetailView.swift
//  HexIOS
//
//  History item detail (design §12, scoped): the full transcript, a playback
//  bar for the retained raw audio (play/pause, waveform progress, duration), and
//  the Coach card — a polished, gradient-tinted rephrase the user can shadow or
//  save. Speaker labels / timecodes / editing are out of scope for now.
//

import HexCore
import SwiftData
import SwiftUI

struct TranscriptDetailView: View {
    let entry: TranscriptEntry
    @State private var audio = AudioPlayer()
    @Environment(\.modelContext) private var modelContext

    /// Coach cards whose example is this transcript — the backlink from a note to
    /// the issues the Coach found in it.
    @Query private var allCards: [CoachCardEntity]
    private var cards: [CoachCardEntity] { allCards.filter { $0.transcriptID == entry.id } }

    private var audioURL: URL? { AudioStore.url(for: entry.audioFilename) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Text(entry.text)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if audioURL != nil {
                    PlayerBar(audio: audio)
                        .hexCard()
                }

                coachCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .task { if let url = audioURL { audio.load(url) } }
        .onDisappear { audio.stop() }
    }

    /// "• DICTATION · date" — the source + timestamp line.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.kind.systemImage)
            Text(entry.kind.label.uppercased())
            if let app = entry.sourceAppName { Text("· \(app)") }
            Spacer()
            Text(entry.date, format: .dateTime.month().day().hour().minute())
        }
        .font(.caption.weight(.semibold))
        .tracking(0.5)
        .foregroundStyle(.secondary)
    }

    // MARK: - Coaching backlink

    /// The first improvement card with a native rewrite — the one the Coach card
    /// invites the user to practice.
    private var rewriteCard: CoachCardEntity? {
        cards.first { $0.kind == .improvement && $0.nativeRewrite != nil }
    }

    /// The first "win" — a positive habit worth celebrating.
    private var winCard: CoachCardEntity? {
        cards.first { $0.kind == .win }
    }

    @ViewBuilder
    private var coachCard: some View {
        if entry.coachAnalyzedAt == nil {
            Label("Not reviewed by the Coach yet", systemImage: "hourglass")
                .font(.footnote).foregroundStyle(.secondary)
        } else if let card = rewriteCard, let rewrite = card.nativeRewrite {
            CoachRewriteCard(card: card, rewrite: rewrite, modelContext: modelContext)
        } else if let win = winCard {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(HexTheme.gradientColors[1])
                Text(win.title).font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hexCard()
        } else if cards.isEmpty {
            Label("No coaching notes for this one", systemImage: "checkmark.circle")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// The hero of the detail screen: a soft gradient-tinted card that offers a more
/// natural way to phrase what the user said, with one tap to shadow it aloud and
/// another to save it to the phrasebook.
private struct CoachRewriteCard: View {
    let card: CoachCardEntity
    let rewrite: String
    let modelContext: ModelContext

    @State private var showShadow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("COACH")
            }
            .font(.caption.weight(.bold))
            .tracking(1)
            .foregroundStyle(HexTheme.gradientColors[1])

            Text("A more natural way to say this:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("“\(rewrite)”")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button { showShadow = true } label: {
                    Label("Say it better", systemImage: "waveform")
                }
                .buttonStyle(HexGradientButtonStyle(compact: true))

                Button { saveToPhrasebook() } label: {
                    Image(systemName: card.status == .saved ? "bookmark.fill" : "bookmark")
                        .font(.headline)
                        .foregroundStyle(HexTheme.gradientColors[1])
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous))
        .fullScreenCover(isPresented: $showShadow) {
            ShadowingView(target: rewrite) {}
        }
    }

    /// Bookmark → keep this rephrase in the phrasebook (RC-5).
    private func saveToPhrasebook() {
        card.status = .saved
        try? modelContext.save()
    }
}

private struct PlayerBar: View {
    let audio: AudioPlayer

    var body: some View {
        HStack(spacing: 14) {
            Button { audio.toggle() } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(HexTheme.gradient, in: .circle)
            }
            .buttonStyle(.plain)

            Waveform(progress: audio.progress) { fraction in audio.seek(toFraction: fraction) }
                .frame(height: 40)

            Text(timeString)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var timeString: String {
        let secs = Int((audio.isPlaying ? audio.currentTime : audio.duration).rounded())
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

/// A simple bar waveform with progress fill; tap/drag to scrub.
private struct Waveform: View {
    let progress: Double
    let onSeek: (Double) -> Void

    private let bars = 40

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0 ..< bars, id: \.self) { i in
                    Capsule()
                        .fill(Double(i) / Double(bars) <= progress
                            ? AnyShapeStyle(HexTheme.gradient)
                            : AnyShapeStyle(Color(.tertiaryLabel)))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(i, max: geo.size.height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        onSeek(min(max(value.location.x / geo.size.width, 0), 1))
                    }
            )
        }
    }

    // Deterministic pseudo-waveform so it doesn't reshuffle on each render.
    private func barHeight(_ i: Int, max: CGFloat) -> CGFloat {
        let v = (sin(Double(i) * 1.7) + sin(Double(i) * 0.5) + 2) / 4 // 0…1
        return max * (0.25 + 0.75 * v)
    }
}
