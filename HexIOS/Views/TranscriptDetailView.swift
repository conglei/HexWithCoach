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
import os
import SwiftData
import SwiftUI

struct TranscriptDetailView: View {
    let entry: TranscriptEntry
    @State private var audio = AudioPlayer()
    @State private var showPronunciation = false
    @Environment(\.modelContext) private var modelContext
    @Environment(CoachService.self) private var coach

    /// Coach cards whose example is this transcript — the backlink from a note to
    /// the issues the Coach found in it.
    @Query private var allCards: [CoachCardEntity]
    private var cards: [CoachCardEntity] { allCards.filter { $0.transcriptID == entry.id } }

    private var audioURL: URL? { AudioStore.url(for: entry.audioFilename) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                // When we have word timings + audio, render an interactive
                // transcript: tap a word to jump there, and the spoken word
                // highlights as it plays (bidirectional sync). Otherwise plain text.
                if let words = entry.wordTimings, !words.isEmpty, audioURL != nil {
                    SyncedTranscriptView(words: words, audio: audio)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(entry.text)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if audioURL != nil {
                    PlayerBar(audio: audio)
                        .hexCard()
                }

                // Phoneme-grade pronunciation check (on-device forced alignment).
                // Only shown when the model + dictionary assets are present.
                if audioURL != nil, PronunciationAssets.ready {
                    Button { showPronunciation = true } label: {
                        Label("Check pronunciation", systemImage: "waveform")
                    }
                    .buttonStyle(HexGradientButtonStyle(compact: true))
                }

                coachCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPronunciation) {
            if let audioURL {
                PronunciationSheet(audioURL: audioURL, transcript: entry.text)
            }
        }
        .toolbar {
            if coach.isReady {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await coach.analyzeEntry(entry) }
                    } label: {
                        if coach.isAnalyzing {
                            ProgressView()
                        } else {
                            Label(entry.coachAnalyzedAt == nil ? "Analyze" : "Re-analyze",
                                  systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(coach.isAnalyzing)
                }
            }
        }
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

/// Interactive transcript with bidirectional audio↔text sync: tapping a word
/// seeks the audio there (and starts playing); during playback the word currently
/// being spoken is highlighted. Words + timings come from the ASR (Parakeet).
private struct SyncedTranscriptView: View {
    let words: [WordTiming]
    let audio: AudioPlayer

    /// Index of the word being spoken now — the last word whose start has passed.
    /// Using "last started" keeps the highlight stable through the ~80ms gaps
    /// between words instead of flickering off.
    private var activeIndex: Int? {
        let t = audio.currentTime
        guard t > 0 || audio.isPlaying else { return nil }
        return words.lastIndex { $0.start <= t + 0.02 }
    }

    var body: some View {
        let active = activeIndex
        FlowLayout(spacing: 6, lineSpacing: 8) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let isActive = index == active
                Text(word.word)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        isActive ? AnyShapeStyle(HexTheme.gradient) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audio.seek(toTime: word.start)
                        if !audio.isPlaying { audio.play() }
                    }
                    .animation(.easeOut(duration: 0.1), value: isActive)
            }
        }
    }
}

/// Minimal wrapping layout (words flow left-to-right, wrapping to new lines).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Pronunciation check

/// Locates the phoneme model + vocab + CMUdict. Looks in the app bundle first
/// (Xcode compiles a bundled `.mlpackage` → `.mlmodelc`), then Application Support
/// (`Pronunciation/`) for side-loaded assets during testing.
nonisolated enum PronunciationAssets {
    static var ready: Bool { model() != nil && vocab() != nil && cmudict() != nil }

    static func model() -> URL? {
        Bundle.main.url(forResource: "PhonemeCTC", withExtension: "mlmodelc") ?? sideloaded("PhonemeCTC.mlpackage")
    }
    static func vocab() -> URL? {
        Bundle.main.url(forResource: "phoneme_vocab", withExtension: "json") ?? sideloaded("phoneme_vocab.json")
    }
    static func cmudict() -> URL? {
        Bundle.main.url(forResource: "cmudict", withExtension: "dict") ?? sideloaded("cmudict.dict")
    }

    private static func sideloaded(_ name: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pronunciation", isDirectory: true) else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Runs the on-device pronunciation analyzer for a note and shows per-word /
/// per-phoneme GOP scores. Tap a word to see its phonemes.
private struct PronunciationSheet: View {
    let audioURL: URL
    let transcript: String

    @Environment(\.dismiss) private var dismiss
    @State private var result: PronunciationResult?
    @State private var errorText: String?
    @State private var selectedWord: WordScore?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    resultsView(result)
                } else if let errorText {
                    ContentUnavailableView("Couldn't analyze", systemImage: "waveform.slash", description: Text(errorText))
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analyzing pronunciation…").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Pronunciation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { await analyze() }
    }

    @ViewBuilder
    private func resultsView(_ result: PronunciationResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tap a word to see its sounds. Greener = closer to native.")
                    .font(.footnote).foregroundStyle(.secondary)

                FlowLayout(spacing: 8, lineSpacing: 10) {
                    ForEach(Array(result.words.enumerated()), id: \.offset) { _, word in
                        Button { selectedWord = word } label: {
                            Text(word.word)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(color(for: word.gop), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let word = selectedWord {
                    Divider()
                    Text(word.word).font(.headline)
                    ForEach(Array(word.phonemes.enumerated()), id: \.offset) { _, p in
                        HStack(spacing: 10) {
                            Text(p.symbol).font(.title3.monospaced())
                                .frame(minWidth: 40, alignment: .leading)
                                .foregroundStyle(color(for: p.gop))
                            Text(String(format: "%.2f–%.2fs", p.start, p.end))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "GOP %.2f", p.gop))
                                .font(.caption.monospacedDigit()).foregroundStyle(color(for: p.gop))
                        }
                    }
                }
            }
            .padding()
        }
    }

    /// GOP (≤0) → color. Thresholds are first-pass and tunable.
    private func color(for gop: Double) -> Color {
        if gop >= -0.3 { return .green }
        if gop >= -1.0 { return .orange }
        return .red
    }

    private enum Outcome: Sendable {
        case success(PronunciationResult)
        case failure(String)
    }

    private func analyze() async {
        guard result == nil, errorText == nil else { return }
        let url = audioURL
        let text = transcript
        let task = Task.detached(priority: .userInitiated) { () -> Outcome in
            guard let modelURL = PronunciationAssets.model(),
                  let vocabURL = PronunciationAssets.vocab(),
                  let dictURL = PronunciationAssets.cmudict() else {
                return .failure("Pronunciation model or dictionary missing.")
            }
            guard let analyzer = PronunciationAnalyzer(modelURL: modelURL, vocabURL: vocabURL, cmudictURL: dictURL) else {
                HexLog.pronunciation.error("Analyzer init failed (model/vocab/dict load).")
                return .failure("Couldn't load the pronunciation model.")
            }
            do {
                let samples = try PhonemeRecognizer.loadSamples(url: url)
                let result = try analyzer.analyze(samples: samples, transcript: text)
                return .success(result)
            } catch {
                HexLog.pronunciation.error("analyze threw: \(error.localizedDescription, privacy: .public)")
                return .failure(error.localizedDescription)
            }
        }
        switch await task.value {
        case .success(let r): result = r; selectedWord = r.words.first
        case .failure(let message): errorText = message
        }
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
