//
//  ShadowingView.swift
//  HexIOS
//
//  RC-4 shadowing surface: hear the natural phrasing, then say it back. Presented
//  from a Review card's "Say it better". Offline (on-device TTS + ASR). Styled with
//  the shared HexTheme — a quoted target card, a gradient mic hero, and a growth-
//  framed result.
//

import SwiftUI

struct ShadowingView: View {
    @State private var model: ShadowingModel
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(target: String, onComplete: @escaping () -> Void) {
        _model = State(initialValue: ShadowingModel(target: target))
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

    /// A simple gradient waveform shown while the learner is speaking.
    private var waveform: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { i in
                Capsule()
                    .fill(HexTheme.gradient)
                    .frame(width: 5, height: [14, 26, 18, 32, 20, 28, 16][i])
            }
        }
        .frame(height: 32)
    }

    // MARK: - Result

    private var resultView: some View {
        VStack(spacing: 12) {
            Image(systemName: model.isSuccess ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                .font(.system(size: 44))
                .foregroundStyle(model.isSuccess ? AnyShapeStyle(HexTheme.gradient) : AnyShapeStyle(Color.orange))
            Text(model.isSuccess ? "Nailed it!" : "Close — give it another go")
                .font(.headline)
            if !model.heard.isEmpty {
                Text("You said: “\(model.heard)”")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if model.isSuccess {
                Button("Done") { onComplete(); dismiss() }
                    .buttonStyle(HexGradientButtonStyle())
                    .padding(.top, 4)
            } else {
                GradientMicButton(systemImage: "mic.fill", size: 120) {
                    Task { await model.toggleRecord() }
                }
                .accessibilityLabel("Try again")
                Text("Tap to try again")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .hexCard(padding: 20)
    }
}
