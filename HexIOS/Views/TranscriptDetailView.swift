//
//  TranscriptDetailView.swift
//  HexIOS
//
//  History item detail (design §12, scoped): the full transcript, a playback
//  bar for the retained raw audio (play/pause, waveform progress, duration), and
//  the Coach card — a polished, gradient-tinted rephrase the user can shadow or
//  save. Speaker labels / timecodes / editing are out of scope for now.
//

import VocoCore
import os
import SwiftData
import SwiftUI

struct TranscriptDetailView: View {
    let entry: TranscriptEntry
    /// When arriving from a Coach card, the flagged span to emphasize in the
    /// transcript so the learner can find it in context.
    var highlightSpan: String? = nil
    @State private var audio = AudioPlayer()
    /// Which underlined meaning issue the Coach panel is currently showing. Set by
    /// tapping an underline in the transcript; defaults to the first issue.
    @State private var focusedCardPID: PersistentIdentifier?
    @Environment(\.modelContext) private var modelContext

    /// Coach cards whose example is this transcript — the backlink from a note to
    /// the issues the Coach found in it.
    @Query private var allCards: [CoachCardEntity]
    private var cards: [CoachCardEntity] { allCards.filter { $0.transcriptID == entry.id } }

    private var audioURL: URL? { AudioStore.url(for: entry.audioFilename) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // When we have word timings + audio, render the layered coaching
                    // transcript (CI-9): bidirectional audio↔text sync PLUS the
                    // persisted objective signals (per-word GOP tint, pause/filler
                    // markers) and any keyed meaning spans, all inline. Read-only — it
                    // never triggers analysis. Otherwise plain text.
                    if let words = entry.wordTimings, !words.isEmpty, audioURL != nil {
                        LayeredTranscriptView(
                            words: words,
                            pronunciation: entry.pronunciationResult,
                            cards: cards,
                            audio: audio,
                            // Tapping an underline focuses that issue in the Coach
                            // panel below and scrolls it into view (point 1 fix).
                            onSelectCard: { card in
                                focusedCardPID = card.persistentModelID
                                withAnimation { proxy.scrollTo("coachPanel", anchor: .center) }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(transcriptAttributed)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if audioURL != nil {
                        PlayerBar(audio: audio)
                            .hexCard()
                    }

                    // CI-7 / ADR-0004: the objective lane (GOP + fluency) runs
                    // automatically at capture and persists per note. The summary +
                    // panel below render those persisted results — no manual trigger.
                    pronunciationSummary

                    coachPanel.id("coachPanel")
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .task { if let url = audioURL { audio.load(url) } }
        .onDisappear { audio.stop() }
    }

    /// The transcript with the Coach-flagged span emphasized (when we arrived here
    /// from a card), so the learner can spot it in context. Plain otherwise.
    private var transcriptAttributed: AttributedString {
        var attributed = AttributedString(entry.text)
        if let span = highlightSpan, !span.isEmpty,
           let range = attributed.range(of: span, options: .caseInsensitive) {
            attributed[range].font = .title3.weight(.heavy)
            attributed[range].foregroundColor = HexTheme.gradientColors[0]
        }
        return attributed
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

    // MARK: - Pronunciation summary (objective lane)

    /// "Sounds to work on" — the 1–3 weakest sounds in this note with the
    /// substitution the speaker made and their own example words. Reframes the raw
    /// per-phoneme dump into a digestible theme. Shown only when GOP data exists.
    @ViewBuilder
    private var pronunciationSummary: some View {
        if let result = entry.pronunciationResult {
            let lessons = PronunciationSummary.lessons(from: result)
            if !lessons.isEmpty {
                PronunciationSummaryCard(lessons: lessons)
            }
        }
    }

    // MARK: - Coaching backlink (meaning lenses)

    /// The "win" card — a positive habit worth celebrating.
    private var winCard: CoachCardEntity? {
        cards.first { $0.kind == .win }
    }

    /// The meaning issues to browse in the panel — the same cards that get
    /// underlined in the transcript, in reading order. Falls back to improvement
    /// cards with a rewrite for plain-text notes (no word timings to match against).
    private var panelCards: [CoachCardEntity] {
        if let words = entry.wordTimings, !words.isEmpty {
            let matched = TranscriptDecorator.matchCards(words: words, cards: cards)
            let ordered = matched.keys.sorted().compactMap { matched[$0] }
            if !ordered.isEmpty { return ordered }
        }
        return cards.filter { $0.kind == .improvement && $0.nativeRewrite != nil }
    }

    @ViewBuilder
    private var coachPanel: some View {
        if entry.coachAnalyzedAt == nil {
            Label("Not reviewed by the Coach yet", systemImage: "hourglass")
                .font(.footnote).foregroundStyle(.secondary)
        } else if !panelCards.isEmpty {
            CoachIssuesPanel(cards: panelCards, focusedPID: $focusedCardPID, modelContext: modelContext)
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

// MARK: - Pronunciation summary card

/// "Sounds to work on": the note's weakest sounds as expected → you-said rows.
private struct PronunciationSummaryCard: View {
    let lessons: [PronunciationLesson]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text("SOUNDS TO WORK ON")
            }
            .font(.caption.weight(.bold)).tracking(1)
            .foregroundStyle(HexTheme.gradientColors[1])

            ForEach(lessons) { LessonRow(lesson: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .hexCard()
    }
}

private struct LessonRow: View {
    let lesson: PronunciationLesson

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 6) {
                Text("/\(lesson.expected)/")
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.red)
                if let actual = lesson.actual {
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text("/\(actual)/")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.actual != nil ? "you said /\(lesson.actual!)/ instead" : "came out unclear")
                    .font(.subheadline.weight(.medium))
                if !lesson.exampleWords.isEmpty {
                    Text("in " + lesson.exampleWords.map { "“\($0)”" }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(lesson.count)×").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Browsable coach issues panel

/// The hero panel: browses the note's meaning issues ("1 of N"), showing one
/// rephrase at a time with shadow + save. Tapping an underline in the transcript
/// focuses the matching issue here.
private struct CoachIssuesPanel: View {
    let cards: [CoachCardEntity]
    @Binding var focusedPID: PersistentIdentifier?
    let modelContext: ModelContext

    private var index: Int {
        guard let pid = focusedPID,
              let i = cards.firstIndex(where: { $0.persistentModelID == pid }) else { return 0 }
        return i
    }
    private var current: CoachCardEntity { cards[min(index, cards.count - 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(current.lens.rawValue.uppercased())
                }
                .font(.caption.weight(.bold)).tracking(1)
                .foregroundStyle(HexTheme.gradientColors[1])

                Spacer()

                if cards.count > 1 {
                    HStack(spacing: 14) {
                        Text("\(index + 1) of \(cards.count)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0)
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(index == cards.count - 1)
                    }
                    .font(.headline).foregroundStyle(HexTheme.gradientColors[1])
                }
            }

            CoachIssueBody(card: current, modelContext: modelContext)
                .id(current.persistentModelID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous))
    }

    private func step(_ delta: Int) {
        let next = max(0, min(cards.count - 1, index + delta))
        focusedPID = cards[next].persistentModelID
    }
}

/// One issue's body: the more-natural rephrase (or the card title when there's no
/// rewrite), the "why", and shadow + save actions.
private struct CoachIssueBody: View {
    let card: CoachCardEntity
    let modelContext: ModelContext

    @State private var showShadow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let rewrite = card.nativeRewrite, !rewrite.isEmpty {
                Text("A more natural way to say this:")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("“\(rewrite)”")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(card.title)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !card.detail.isEmpty {
                Text(card.detail).font(.callout).foregroundStyle(.secondary)
            }

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
        .fullScreenCover(isPresented: $showShadow) {
            ShadowingView(target: shadowTarget) {}
        }
    }

    /// Shadow the real, speakable practice sentence when present; else the rewrite.
    private var shadowTarget: String {
        if let practice = card.practiceText, !practice.isEmpty { return practice }
        return card.nativeRewrite ?? card.title
    }

    private func saveToPhrasebook() {
        card.status = .saved
        try? modelContext.save()
    }
}

/// Minimal wrapping layout (words flow left-to-right, wrapping to new lines).
/// Shared with `LayeredTranscriptView`.
struct FlowLayout: Layout {
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

// CI-7 / ADR-0004: the on-demand `PronunciationSheet` (a manual analyze trigger)
// was removed. GOP now runs automatically at capture, is persisted per note, and
// renders inline in `LayeredTranscriptView` — no button, no re-analysis.

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
