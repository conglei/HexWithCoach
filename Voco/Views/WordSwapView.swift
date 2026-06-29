//
//  WordSwapView.swift
//  Voco
//
//  CF-2 — the `wordSwap` drill surface (the vocabulary / naturalness drill). This
//  is the *interaction* layer for `WordSwapDrill`: a quick recognition warm-up
//  (your phrasing → the native choice, hear it), then **production** — the learner
//  says the more-natural phrasing aloud and the on-device `WordSwapJudge` scores
//  whether they produced it. Feedback is respectful ("the native choice here is X"),
//  never a harsh "wrong".
//
//  It mirrors `ShadowingView`'s entry-point shape (`onComplete` fires once when the
//  learner finishes) so the Practice surface can launch either drill from a card,
//  chosen by the card's lens. Unlike shadowing there is no GOP — the learning here
//  is the word *choice*, not the sounds.
//

import VocoCore
import SwiftUI

struct WordSwapView: View {
    @State private var model: WordSwapModel
    /// Fires once when the learner finishes the drill (Done). Mirrors
    /// `ShadowingView.onComplete` so Practice can treat both drills uniformly.
    let onComplete: () -> Void
    /// Reports the scored attempt (0…1 + win) to a caller that persists it as a
    /// `PracticeAttempt` tagged `.wordSwap`. Default no-op keeps standalone callers
    /// simple.
    let onScored: (WordSwapResult) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        drill: WordSwapDrill,
        onScored: @escaping (WordSwapResult) -> Void = { _ in },
        onComplete: @escaping () -> Void
    ) {
        _model = State(initialValue: WordSwapModel(drill: drill))
        self.onScored = onScored
        self.onComplete = onComplete
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                if model.phase == .warmUp {
                    warmUpSection
                } else if model.phase == .done {
                    resultSection
                } else {
                    productionSection
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
        #if DEBUG
        // DEBUG-only: a seeded screenshot / QA run can jump straight to the scored
        // result by injecting a canned spoken production (`-VOCOAutoWordSwapSay`
        // followed by the text), so the verdict UI is verifiable without the mic.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-VOCOAutoWordSwapSay"), i + 1 < args.count else { return }
            model.debugInjectProduction(args[i + 1])
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.secondary)
                }
            }
            Text("Say it more naturally")
                .font(.title2.weight(.bold))
            Text("Reach for the native word choice")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 1. Recognition warm-up (before → after)

    private var warmUpSection: some View {
        VStack(spacing: 16) {
            // The before/after contrast — recognition primes production.
            VStack(spacing: 14) {
                if let original = model.originalSpan, !original.isEmpty {
                    labeledPhrase("YOU SAID", text: original, tint: .secondary, strike: false)
                    Image(systemName: "arrow.down")
                        .font(.headline).foregroundStyle(HexTheme.gradient)
                }
                labeledPhrase("MORE NATURAL", text: model.targetPhrase, tint: HexTheme.gradientColors[0], strike: false)

                Button { model.speakTarget() } label: {
                    Label("Hear it", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
                .tint(HexTheme.gradientColors[0])
            }
            .hexCard(padding: 20)

            Text("Now say it yourself — in your own sentence is fine.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                model.beginProduction()
            } label: {
                Label("I'm ready — say it", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HexGradientButtonStyle())
        }
    }

    private func labeledPhrase(_ label: String, text: String, tint: Color, strike: Bool) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(.secondary)
            Text("“\(text)”")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .strikethrough(strike)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 2. Production (record → transcribe)

    private var productionSection: some View {
        VStack(spacing: 16) {
            // Keep the target visible while producing.
            VStack(spacing: 8) {
                Text("SAY THE NATURAL VERSION")
                    .font(.caption.weight(.bold)).tracking(1)
                    .foregroundStyle(HexTheme.gradientColors[0])
                Text("“\(model.targetPhrase)”")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .hexCard(padding: 16)

            GradientMicButton(
                systemImage: model.phase == .recording ? "stop.fill" : "mic.fill",
                size: 120
            ) {
                Task { await model.toggleRecord() }
            }
            .disabled(model.phase == .transcribing)
            .accessibilityLabel(model.phase == .recording ? "Stop" : "Record your phrasing")

            if model.phase == .recording { waveform }

            if model.phase == .transcribing {
                ProgressView("Checking…")
            } else {
                Text(model.phase == .recording ? "Listening… say the natural phrasing" : "Tap to say it")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

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

    // MARK: - 3. Result (judge verdict + respectful feedback)

    @ViewBuilder
    private var resultSection: some View {
        if let result = model.result {
            VStack(spacing: 16) {
                verdictCard(result)
                producedCard
                actions
            }
        }
    }

    private func verdictCard(_ result: WordSwapJudge.Result) -> some View {
        VStack(spacing: 10) {
            Image(systemName: result.isWin ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(result.isWin ? AnyShapeStyle(HexTheme.gradient) : AnyShapeStyle(Color.orange))
            Text(result.feedback)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            // Always show the native target so the win is reinforced and a miss is
            // shown the answer — never just "wrong".
            VStack(spacing: 4) {
                Text("THE NATURAL CHOICE")
                    .font(.caption2.weight(.bold)).tracking(1)
                    .foregroundStyle(.secondary)
                Text("“\(model.targetPhrase)”")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HexTheme.gradientColors[0])
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .hexCard(padding: 20)
    }

    private var producedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOU SAID")
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(.secondary)
            Text(model.heard.isEmpty ? "—" : "“\(model.heard)”")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button { model.speakTarget() } label: {
                    Label("Hear native", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(HexTheme.gradientColors[0])
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hexCard(padding: 16)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            Button {
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

    private func reportAndFinish() {
        onScored(WordSwapResult(score: model.score, isWin: model.isWin))
        onComplete()
        dismiss()
    }
}

/// One finished `wordSwap` attempt, reported so the Practice surface can persist a
/// `PracticeAttempt` tagged `.wordSwap`. The single `score` reuses
/// `PracticeAttempt.perSegmentScores` (a one-element array) — no GOP for this kind.
struct WordSwapResult {
    let score: Double
    let isWin: Bool
}
