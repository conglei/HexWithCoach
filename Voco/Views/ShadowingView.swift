//
//  ShadowingView.swift
//  HexIOS
//
//  RC-4 shadowing surface: hear the natural phrasing, then say it back. Presented
//  from a Review card's "Say it better". Offline (on-device TTS + ASR). Styled with
//  the shared HexTheme — a quoted target card, a gradient mic hero, and a growth-
//  framed result.
//

import VocoCore
import SwiftUI

struct ShadowingView: View {
    @State private var model: ShadowingModel
    let onComplete: () -> Void
    /// Optional per-segment score sink for the multi-segment paste session (PR-3).
    /// Reports the ASR match score and any GOP delta when the learner finishes a
    /// segment. The default no-op keeps the single-phrase Review/coach callers
    /// (which only need `onComplete`) untouched.
    let onScored: (ShadowingSegmentResult) -> Void
    /// Whether finishing should dismiss the surrounding presentation. true (the
    /// default) preserves today's single-shot behavior for every existing caller
    /// (Review's "Say it better", coach drills, TranscriptDetailView): the view
    /// owns its own cover and closes it on Done. The multi-segment paste session
    /// (PR-3) sets this false — it embeds `ShadowingView` directly in its cover
    /// with NO presentation boundary, so an internal `dismiss()` would close the
    /// whole session. When false, finishing drives advancement purely via
    /// `onScored`/`onComplete` and the session owns the dismiss.
    let dismissOnComplete: Bool
    /// Which flagged word's phoneme detail is currently expanded (SR-2), or nil.
    @State private var expandedWord: Int?
    @Environment(\.dismiss) private var dismiss

    init(
        target: String,
        dismissOnComplete: Bool = true,
        onScored: @escaping (ShadowingSegmentResult) -> Void = { _ in },
        onComplete: @escaping () -> Void
    ) {
        _model = State(initialValue: ShadowingModel(target: target))
        self.dismissOnComplete = dismissOnComplete
        self.onScored = onScored
        self.onComplete = onComplete
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                targetCard

                if model.phase == .done {
                    resultView
                } else {
                    micSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .alert(
            "Couldn't record",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
            presenting: model.errorMessage
        ) { _ in Button("OK", role: .cancel) {} } message: { Text($0) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Say it better")
                .font(.title2.weight(.bold))
            Text("Practice this phrase")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Target phrase

    private var targetCard: some View {
        VStack(spacing: 16) {
            Text("“\(model.target)”")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button { model.speak() } label: {
                Label("Hear it", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .tint(HexTheme.gradientColors[0])
        }
        .hexCard(padding: 20)
    }

    // MARK: - Mic hero

    private var micSection: some View {
        VStack(spacing: 16) {
            Text("● YOUR TURN — SAY IT")
                .font(.caption.weight(.bold)).tracking(1)
                .foregroundStyle(HexTheme.gradientColors[0])

            GradientMicButton(
                systemImage: model.phase == .recording ? "stop.fill" : "mic.fill",
                size: 120
            ) {
                Task { await model.toggleRecord() }
            }
            .disabled(model.phase == .transcribing)
            .accessibilityLabel(model.phase == .recording ? "Stop" : "Record your repeat")

            if model.phase == .recording {
                waveform
            }

            if model.phase == .transcribing {
                ProgressView("Checking…")
            } else {
                Text(model.phase == .recording ? "Listening… repeat the phrase out loud" : "Tap to repeat it")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// A live gradient waveform driven by the learner's actual mic level while
    /// speaking — mirrors the dictation page's metering, scaled to this hero.
    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(HexTheme.gradient)
                    .frame(width: 3, height: 4 + level * 28)
            }
        }
        .frame(height: 32)
        .animation(.linear(duration: 0.05), value: model.levels)
    }

    // MARK: - Result (SR-2 redesign)

    /// The redesigned result: a dual-signal verdict (ASR match vs GOP issues kept
    /// separate), the phrase tinted word-by-word with tappable flagged words, a
    /// focused `PhonemeAnchor` issue list, compare playback (native + yours), the
    /// closed-loop progress delta, and Try again / Done.
    private var resultView: some View {
        VStack(spacing: 16) {
            verdictCard
            if model.attemptScores != nil {
                phraseCard
            }
            if !model.resultIssues.isEmpty {
                issuesCard
            }
            comparePlaybackCard
            if let comparison = model.gopComparison, !comparison.isEmpty {
                VStack { progressSection(comparison) }.hexCard(padding: 16)
            }
            actions
        }
    }

    // MARK: Verdict

    private var verdictCard: some View {
        let verdict = model.verdict
        return VStack(spacing: 10) {
            Image(systemName: verdict.isWin ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(verdict.isWin ? AnyShapeStyle(HexTheme.gradient) : AnyShapeStyle(Color.orange))
            Text(verdict.headline)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            // Two SEPARATE signals — never conflated.
            HStack(spacing: 10) {
                signalChip(
                    ok: verdict.rightWords,
                    okText: "Right words",
                    badText: "Words off",
                    icon: verdict.rightWords ? "text.bubble.fill" : "text.bubble"
                )
                if let count = verdict.soundIssueCount {
                    signalChip(
                        ok: count == 0,
                        okText: "Sounds clear",
                        badText: "\(count) sound\(count == 1 ? "" : "s") to polish",
                        icon: count == 0 ? "waveform" : "waveform.badge.exclamationmark"
                    )
                }
            }
            if !model.heard.isEmpty, !verdict.rightWords {
                Text("Heard: “\(model.heard)”")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .hexCard(padding: 20)
    }

    private func signalChip(ok: Bool, okText: String, badText: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(ok ? okText : badText).font(.footnote.weight(.semibold))
        }
        .foregroundStyle(ok ? Color.green : Color.orange)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background((ok ? Color.green : Color.orange).opacity(0.12), in: Capsule())
    }

    // MARK: Word-level phrase

    private var phraseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR PHRASE")
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(.secondary)

            FlowChipsLayout(spacing: 6, lineSpacing: 8) {
                ForEach(model.resultWords) { word in
                    WordChip(word: word, expanded: expandedWord == word.index) {
                        guard word.isFlagged else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            expandedWord = (expandedWord == word.index) ? nil : word.index
                        }
                    }
                }
            }

            if let index = expandedWord,
               let word = model.resultWords.first(where: { $0.index == index }),
               !word.phonemes.isEmpty {
                WordPhonemeDetail(word: word)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hexCard(padding: 16)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(.green, "good")
            legendDot(.orange, "close")
            legendDot(.red, "off")
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: Focused issues (PhonemeAnchor)

    private var issuesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SOUNDS TO POLISH")
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(.secondary)

            ForEach(model.resultIssues) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    if !issue.word.isEmpty {
                        Text("in “\(issue.word)”")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HexTheme.gradientColors[1])
                    }
                    Text(issue.detail)
                        .font(.subheadline.weight(.medium))
                    if let tip = issue.tip {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "mouth").font(.caption2).foregroundStyle(.secondary)
                            Text(tip).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if issue.id != model.resultIssues.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hexCard(padding: 16)
    }

    // MARK: Compare playback

    private var comparePlaybackCard: some View {
        HStack(spacing: 12) {
            Button { model.speak() } label: {
                Label("Hear native", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(HexTheme.gradientColors[0])

            Button { model.playRecording() } label: {
                Label(model.isPlayingRecording ? "Playing…" : "Hear yours",
                      systemImage: model.isPlayingRecording ? "waveform" : "play.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(HexTheme.gradientColors[1])
            .disabled(!model.hasRecording)
        }
    }

    // MARK: Actions — Try again (primary) / Done (secondary)

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                expandedWord = nil
                Task { await model.toggleRecord() }
            } label: {
                Label("Try again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HexGradientButtonStyle())

            Button("Done") { reportAndFinish() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    /// Report this segment's score to the session sink, then run the legacy
    /// completion hook and dismiss. Both callbacks fire exactly once per finish.
    private func reportAndFinish() {
        onScored(
            ShadowingSegmentResult(
                score: model.score,
                gopDelta: model.gopComparison.map(Self.meanDelta)
            )
        )
        onComplete()
        // Only own the dismiss for standalone single-shot callers. When embedded
        // in the paste session (dismissOnComplete == false), `onComplete` advances
        // the session and the session owns the cover's dismiss — calling it here
        // would synchronously tear down the whole session after segment 0.
        if dismissOnComplete { dismiss() }
    }

    /// Mean per-phoneme GOP delta for an attempt (positive = closer to native).
    /// Persisted as `PracticeAttempt.gopDelta`. nil-comparison → no value.
    private static func meanDelta(_ comparison: ShadowingGOP.Comparison) -> Double {
        let deltas = comparison.phonemes.map(\.delta)
        guard !deltas.isEmpty else { return 0 }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    // MARK: - CI-11 closed-loop progress (2nd attempt onward)

    /// Per-phoneme progress since the previous attempt — "know my progress". Only
    /// shown when the model produced a comparison (i.e. there was a prior attempt);
    /// the first attempt shows the breakdown above without this section.
    @ViewBuilder
    private func progressSection(_ comparison: ShadowingGOP.Comparison) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROGRESS vs. last try")
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(.secondary)

            let improved = comparison.improved
            if !improved.isEmpty {
                deltaRow(
                    icon: "arrow.up.right.circle.fill",
                    tint: .green,
                    text: improved.map { "/\($0.symbol)/" }.joined(separator: " ") + " improved ↑"
                )
            }
            let stillWeak = comparison.stillWeak
            if !stillWeak.isEmpty {
                deltaRow(
                    icon: "circle.dashed",
                    tint: .red,
                    text: stillWeak.map { "/\($0.symbol)/" }.joined(separator: " ") + " still needs work"
                )
            }
            let regressed = comparison.regressed
            if !regressed.isEmpty {
                deltaRow(
                    icon: "arrow.down.right.circle.fill",
                    tint: .orange,
                    text: "Watch: " + regressed.map { "/\($0.symbol)/" }.joined(separator: " ")
                )
            }
            if improved.isEmpty, stillWeak.isEmpty, regressed.isEmpty {
                deltaRow(icon: "equal.circle.fill", tint: .secondary, text: "About the same as last time")
            }

            // The per-phoneme chips, colored by the attempt's quality band.
            FlowChips(deltas: comparison.phonemes)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func deltaRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.footnote.weight(.medium))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - SR-2 word rendering

/// One word of the rendered phrase, tinted by its per-word GOP quality. Flagged
/// (`.off`) words are underlined and tappable to expand their phoneme detail; words
/// without GOP (out-of-dictionary / no model) render plain. `good`/`close` words are
/// tinted but not interactive.
private struct WordChip: View {
    let word: ShadowingResult.Word
    let expanded: Bool
    let onTap: () -> Void

    var body: some View {
        Text(word.text)
            .font(.title3.weight(.medium))
            .foregroundStyle(color)
            .underline(word.isFlagged, color: color.opacity(0.6))
            .padding(.horizontal, word.isFlagged ? 4 : 0)
            .background(
                word.isFlagged
                    ? AnyShapeStyle(Color.red.opacity(expanded ? 0.18 : 0.10))
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(word.isFlagged ? .isButton : [])
    }

    private var color: Color {
        switch word.quality {
        case .good: return .green
        case .close: return .orange
        case .off: return .red
        case nil: return .primary
        }
    }
}

/// The expanded phoneme detail for a tapped flagged word: each expected phoneme as
/// a chip tinted by its own GOP, with the substitution it came out as when one
/// exists. Lets the learner see exactly which sound inside the word was off.
private struct WordPhonemeDetail: View {
    let word: ShadowingResult.Word

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sounds in “\(word.text)”")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            FlowChipsLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(word.phonemes.enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 3) {
                        Text("/\(p.symbol)/").font(.caption.monospaced().weight(.semibold))
                        if let said = p.actualSymbol, said != p.symbol {
                            Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).opacity(0.7)
                            Text("/\(said)/").font(.caption.monospaced())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(chipColor(p.gop), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chipColor(_ gop: Double) -> Color {
        switch GOPColoring.bucket(forGOP: gop) {
        case .good: return .green
        case .fair: return .orange
        case .weak: return .red
        case .neutral: return .gray
        }
    }
}

/// One finished segment's outcome, reported to the paste session (PR-3) so it can
/// collect per-segment scores and the (optional) GOP delta for a `PracticeAttempt`.
/// (Named `…SegmentResult` to avoid colliding with VocoCore's `ShadowingResult`
/// presentation namespace used by the redesigned result screen.)
struct ShadowingSegmentResult {
    /// ASR match score for the segment (0…1), mirroring `ShadowingModel.score`.
    let score: Double
    /// Mean per-phoneme GOP delta vs. the previous attempt, when the pronunciation
    /// model produced a comparison; nil otherwise (first attempt / no model).
    let gopDelta: Double?
}

/// The attempt's phonemes as small colored chips: green = native-clean, orange =
/// okay, red = still weak. Arrow marks a sound that crossed up since last try.
private struct FlowChips: View {
    let deltas: [ShadowingGOP.PhonemeDelta]

    var body: some View {
        FlowChipsLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(deltas.enumerated()), id: \.offset) { _, d in
                HStack(spacing: 2) {
                    if d.verdict == .improved { Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold)) }
                    Text(d.symbol).font(.caption.monospaced())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(color(for: d.attemptQuality), in: Capsule())
            }
        }
    }

    private func color(for quality: ShadowingGOP.Quality) -> Color {
        switch quality {
        case .good: return .green
        case .okay: return .orange
        case .weak: return .red
        }
    }
}

/// Minimal wrapping layout for the phoneme chips (kept local so this view doesn't
/// depend on TranscriptDetailView's private FlowLayout).
private struct FlowChipsLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
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
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
