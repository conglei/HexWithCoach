//
//  LayeredTranscriptView.swift
//  HexIOS
//
//  CI-9 — the synced transcript IS the coaching surface. On one timeline it
//  renders the persisted *objective* signals (per-word GOP tint, long-pause and
//  filler markers) plus, when present, the (keyed) meaning spans the LLM lane
//  flagged. Everything here is READ-ONLY rendering of data already persisted with
//  the note (ADR-0004): it never triggers analysis and never prompts a download.
//
//  Tapping a word opens its phoneme/GOP detail; tapping a flagged span opens the
//  Coach card it came from. When a note has no objective data yet, words simply
//  render neutral — the plain synced transcript, gracefully.
//

import HexCore
import SwiftUI

/// The layered, interactive transcript. Bidirectional audio↔text sync is kept
/// from the original synced view (tap to seek, active word highlights during
/// playback); on top of that each word carries its persisted GOP tint, pause and
/// filler markers, and meaning-span underlines.
struct LayeredTranscriptView: View {
    let words: [WordTiming]
    /// Persisted per-note GOP result (CI-3), or nil when none was captured.
    let pronunciation: PronunciationResult?
    /// Coach cards whose example is this note — their `originalSpan`s become the
    /// (keyed) meaning underlines. Empty when keyless / no LLM insights yet.
    let cards: [CoachCardEntity]
    let audio: AudioPlayer
    /// Tapping a meaning underline reports its card to the host so the host can
    /// focus it in the browsable Coach panel ("1 of N"). When nil, the tap opens a
    /// standalone detail sheet instead.
    var onSelectCard: ((CoachCardEntity) -> Void)? = nil

    /// Tap a word → its phoneme/GOP detail (objective lane).
    @State private var selectedWord: WordScore?
    /// Tap a meaning span → the card it came from (LLM lane).
    @State private var selectedCard: CoachCardEntity?

    /// Per-display-word fused decoration, computed once from the persisted data.
    private var decorated: [DecoratedWord] {
        TranscriptDecorator.decorate(words: words, pronunciation: pronunciation, cards: cards)
    }

    /// Index of the word being spoken now — the last word whose start has passed.
    /// "Last started" keeps the highlight stable through the ~80ms inter-word gaps
    /// instead of flickering off.
    private var activeIndex: Int? {
        let t = audio.currentTime
        guard t > 0 || audio.isPlaying else { return nil }
        return words.lastIndex { $0.start <= t + 0.02 }
    }

    var body: some View {
        let active = activeIndex
        let items = decorated
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 6, lineSpacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    wordView(item, isActive: index == active)
                }
            }

            if !legendBuckets.isEmpty || hasMarkers {
                legend
            }
        }
        .sheet(item: $selectedWord) { word in
            PhonemeDetailSheet(word: word)
        }
        .sheet(item: $selectedCard) { card in
            CoachCardDetailSheet(card: card)
        }
    }

    @ViewBuilder
    private func wordView(_ item: DecoratedWord, isActive: Bool) -> some View {
        let bucket = item.bucket
        Text(item.text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                isActive
                    ? AnyShapeStyle(HexTheme.gradient)
                    : AnyShapeStyle(tint(for: bucket)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            // Meaning-span underline (grammar / word-choice). Absent → no underline.
            .overlay(alignment: .bottom) {
                if item.card != nil {
                    Rectangle()
                        .fill(HexTheme.gradientColors[0])
                        .frame(height: 2)
                        .offset(y: 3)
                }
            }
            // Pause / filler markers ride just above the word.
            .overlay(alignment: .topTrailing) {
                if let marker = item.marker {
                    Text(marker.glyph)
                        .font(.caption2)
                        .offset(x: 4, y: -8)
                        .accessibilityLabel(marker.accessibilityLabel)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { handleTap(item) }
            .animation(.easeOut(duration: 0.1), value: isActive)
    }

    /// Tap priority: a flagged meaning span opens its card; otherwise a scored
    /// word opens its phoneme detail; a plain word just seeks the audio.
    private func handleTap(_ item: DecoratedWord) {
        if let card = item.card {
            if let onSelectCard { onSelectCard(card) } else { selectedCard = card }
        } else if let score = item.score {
            selectedWord = score
        } else {
            audio.seek(toTime: item.timing.start)
            if !audio.isPlaying { audio.play() }
        }
    }

    /// Soft GOP tint behind a word — warmer = worse. `neutral` (no data) is clear,
    /// so an unanalyzed note reads as the plain transcript.
    private func tint(for bucket: GOPColoring.Bucket) -> Color {
        switch bucket {
        case .good: return Color.green.opacity(0.16)
        case .fair: return Color.orange.opacity(0.22)
        case .weak: return Color.red.opacity(0.24)
        case .neutral: return .clear
        }
    }

    // MARK: - Legend

    private var legendBuckets: [GOPColoring.Bucket] {
        let present = Set(decorated.map(\.bucket)).subtracting([.neutral])
        return [.good, .fair, .weak].filter { present.contains($0) }
    }

    private var hasMarkers: Bool { decorated.contains { $0.marker != nil } || decorated.contains { $0.card != nil } }

    private var legend: some View {
        FlowLayout(spacing: 12, lineSpacing: 6) {
            ForEach(legendBuckets, id: \.self) { bucket in
                legendChip(swatch: tint(for: bucket), label: legendLabel(for: bucket))
            }
            if decorated.contains(where: { $0.marker == .longPause }) {
                legendChip(glyph: TranscriptDecorator.Marker.longPause.glyph, label: "long pause")
            }
            if decorated.contains(where: { $0.marker == .filler }) {
                legendChip(glyph: TranscriptDecorator.Marker.filler.glyph, label: "filler")
            }
            if decorated.contains(where: { $0.card != nil }) {
                legendChip(underline: true, label: "word choice / grammar")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendLabel(for bucket: GOPColoring.Bucket) -> String {
        switch bucket {
        case .good: return "clear"
        case .fair: return "slight"
        case .weak: return "work on"
        case .neutral: return ""
        }
    }

    private func legendChip(swatch: Color? = nil, glyph: String? = nil, underline: Bool = false, label: String) -> some View {
        HStack(spacing: 4) {
            if let swatch {
                RoundedRectangle(cornerRadius: 3).fill(swatch).frame(width: 12, height: 12)
            } else if let glyph {
                Text(glyph)
            } else if underline {
                Rectangle().fill(HexTheme.gradientColors[0]).frame(width: 14, height: 2)
            }
            Text(label)
        }
    }
}

// MARK: - Fusion (pure-ish view-model layer)

/// A display word fused with whatever persisted signals reference it: its GOP
/// score (objective), a pause/filler marker (objective), and a meaning card
/// (LLM). All fields are optional so an unanalyzed note decorates to nothing.
struct DecoratedWord {
    let timing: WordTiming
    let score: WordScore?
    let marker: TranscriptDecorator.Marker?
    let card: CoachCardEntity?

    var text: String { timing.word }
    var bucket: GOPColoring.Bucket { GOPColoring.bucket(forGOP: score?.gop) }
}

/// Aligns persisted signals onto the display words. Read-only; no analysis. Kept
/// out of the View body so the matching logic stays simple and self-contained.
enum TranscriptDecorator {
    enum Marker: Equatable {
        case longPause   // a long silent gap *before* this word
        case filler      // this word is a filler token (um / uh / like / …)

        var glyph: String {
            switch self {
            case .longPause: return "···"
            case .filler: return "˚"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .longPause: return "long pause before this word"
            case .filler: return "filler word"
            }
        }
    }

    /// A gap (previous word end → this word start) longer than this reads as a
    /// long pause inline. Matches `FluencyAnalyzer.longPauseThresholdSec`.
    static let longPauseSec = FluencyAnalyzer.longPauseThresholdSec

    static func decorate(
        words: [WordTiming],
        pronunciation: PronunciationResult?,
        cards: [CoachCardEntity]
    ) -> [DecoratedWord] {
        let scores = matchScores(words: words, pronunciation: pronunciation)
        let cardByIndex = matchCards(words: words, cards: cards)

        return words.enumerated().map { index, timing in
            var marker: Marker? = nil
            // Long pause: a big silent gap before this word.
            if index > 0 {
                let gap = timing.start - words[index - 1].end
                if gap > longPauseSec { marker = .longPause }
            }
            // Filler word (overrides the pause marker — the word itself is the cue).
            if isFiller(timing.word) { marker = .filler }

            return DecoratedWord(
                timing: timing,
                score: scores[index],
                marker: marker,
                card: cardByIndex[index]
            )
        }
    }

    /// Match each display word to its pronunciation `WordScore`. The analyzer only
    /// scores words it found in CMUdict (a subset, same order), so we walk both
    /// streams forward and pair on normalized equality. Words with no score stay
    /// nil (→ neutral tint).
    static func matchScores(words: [WordTiming], pronunciation: PronunciationResult?) -> [WordScore?] {
        var result = [WordScore?](repeating: nil, count: words.count)
        guard let scored = pronunciation?.words, !scored.isEmpty else { return result }
        var s = 0
        for i in words.indices where s < scored.count {
            if normalize(words[i].word) == normalize(scored[s].word) {
                result[i] = scored[s]
                s += 1
            }
        }
        return result
    }

    /// Map cards onto display words by locating each card's `originalSpan` as a
    /// run of consecutive words. The first word of a matched span carries the card
    /// (the underline + tap target). Spans that don't match any run are dropped.
    static func matchCards(words: [WordTiming], cards: [CoachCardEntity]) -> [Int: CoachCardEntity] {
        var out: [Int: CoachCardEntity] = [:]
        let normWords = words.map { normalize($0.word) }
        for card in cards {
            guard let span = card.originalSpan, !span.isEmpty else { continue }
            let needle = FluencyTokenize(span)
            guard !needle.isEmpty else { continue }
            if let start = firstRun(of: needle, in: normWords), out[start] == nil {
                out[start] = card
            }
        }
        return out
    }

    /// First index where `needle` appears as a consecutive run in `haystack`.
    private static func firstRun(of needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0 ... (haystack.count - needle.count) where Array(haystack[i ..< i + needle.count]) == needle {
            return i
        }
        return nil
    }

    private static func isFiller(_ word: String) -> Bool {
        FluencyAnalyzer.defaultSingleWordFillers.contains(normalize(word))
    }

    /// Lowercase + strip edge punctuation, matching how `FluencyAnalyzer`
    /// tokenizes so filler/span matching agrees with the persisted signals.
    private static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    private static func FluencyTokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Detail sheets (reuse the existing GOP coloring + card shape)

/// Tap a word → its phonemes with per-phoneme GOP. Renders the persisted GOP
/// result inline, read-only — no on-demand analysis (the objective lane runs
/// automatically at capture; CI-7).
private struct PhonemeDetailSheet: View {
    let word: WordScore
    @Environment(\.dismiss) private var dismiss

    /// The single worst sound in this word — what to lead with.
    private var weakest: PhonemeScore? {
        word.phonemes
            .filter { GOPColoring.bucket(forGOP: $0.gop) == .weak }
            .min { $0.gop < $1.gop }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(word.word).font(.largeTitle.weight(.bold))

                    if let w = weakest {
                        weakestCallout(w)
                    } else {
                        Label("This sounded clear", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                    }

                    Text("EVERY SOUND")
                        .font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                    ForEach(Array(word.phonemes.enumerated()), id: \.offset) { _, p in
                        phonemeRow(p)
                    }

                    Text("Closer to 0 = closer to native. Read-only.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Pronunciation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    /// The hero: the expected sound vs. what the learner actually produced.
    @ViewBuilder private func weakestCallout(_ p: PhonemeScore) -> some View {
        let substituted = p.actualSymbol.map { $0 != p.symbol } ?? false
        VStack(alignment: .leading, spacing: 8) {
            Text("WORK ON THIS SOUND")
                .font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(color(for: p.gop))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ipa(p.symbol, label: "expected", color: color(for: p.gop))
                if substituted, let actual = p.actualSymbol {
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    ipa(actual, label: "you said", color: .secondary)
                }
            }
            Text(substituted
                 ? "Aim for /\(p.symbol)/ — it came out closer to /\(p.actualSymbol ?? "")/."
                 : "The /\(p.symbol)/ sound came out unclear.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color(for: p.gop).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ipa(_ symbol: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("/\(symbol)/").font(.system(.largeTitle, design: .monospaced).weight(.bold)).foregroundStyle(color)
        }
    }

    @ViewBuilder private func phonemeRow(_ p: PhonemeScore) -> some View {
        let showActual = (p.actualSymbol.map { $0 != p.symbol } ?? false)
            && GOPColoring.bucket(forGOP: p.gop) != .good
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(p.symbol).font(.title3.monospaced()).foregroundStyle(color(for: p.gop))
                if showActual, let actual = p.actualSymbol {
                    Text("→ \(actual)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 64, alignment: .leading)
            Text(String(format: "%.2f–%.2fs", p.start, p.end))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "GOP %.2f", p.gop))
                .font(.caption.monospacedDigit()).foregroundStyle(color(for: p.gop))
        }
    }

    /// GOP bucket → color, via the shared deterministic mapping.
    private func color(for gop: Double) -> Color {
        switch GOPColoring.bucket(forGOP: gop) {
        case .good: return .green
        case .fair: return .orange
        case .weak: return .red
        case .neutral: return .secondary
        }
    }
}

/// Tap a meaning span → the Coach card it came from. A compact read-only view of
/// the persisted card (title, the original→rewrite contrast, detail).
private struct CoachCardDetailSheet: View {
    let card: CoachCardEntity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(card.lens.rawValue.uppercased())
                    }
                    .font(.caption.weight(.bold)).tracking(1)
                    .foregroundStyle(HexTheme.gradientColors[1])

                    Text(card.title).font(.title3.weight(.bold))

                    if let original = card.originalSpan, !original.isEmpty {
                        labeled("You said", text: "“\(original)”")
                    }
                    if let rewrite = card.nativeRewrite, !rewrite.isEmpty {
                        labeled("More natural", text: "“\(rewrite)”")
                    }
                    if !card.detail.isEmpty {
                        Text(card.detail).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func labeled(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
            Text(text).font(.body.weight(.medium))
        }
    }
}

// Sheet item conformance for the tap targets (read-only display).
extension WordScore: Identifiable {
    public var id: String { word + phonemes.map(\.symbol).joined() }
}
