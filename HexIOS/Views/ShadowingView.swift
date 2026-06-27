//
//  ShadowingView.swift
//  HexIOS
//
//  RC-4 shadowing surface: hear the natural phrasing, then say it back. Presented
//  from a Review card's "Say it better". Offline (on-device TTS + ASR).
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
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Say it like this").font(.subheadline).foregroundStyle(.secondary)
            Text(model.target)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button { model.speak() } label: {
                Label("Listen", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)

            Spacer()

            if model.phase == .transcribing {
                ProgressView("Checking…")
            } else if model.phase == .done {
                resultView
            } else {
                Text(model.phase == .recording ? "Listening…" : "Tap to repeat it")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            recordButton
            Spacer()
        }
        .padding()
        .alert(
            "Couldn't record",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
            presenting: model.errorMessage
        ) { _ in Button("OK", role: .cancel) {} } message: { Text($0) }
    }

    private var recordButton: some View {
        Button { Task { await model.toggleRecord() } } label: {
            Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(model.phase == .recording ? Color.red : Color.accentColor, in: .circle)
        }
        .disabled(model.phase == .transcribing)
        .accessibilityLabel(model.phase == .recording ? "Stop" : "Record your repeat")
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            Image(systemName: model.isSuccess ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                .font(.system(size: 40))
                .foregroundStyle(model.isSuccess ? Color.green : Color.orange)
            Text(model.isSuccess ? "Nailed it!" : "Close — give it another go")
                .font(.headline)
            if !model.heard.isEmpty {
                Text("You said: “\(model.heard)”")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if model.isSuccess {
                Button("Done") { onComplete(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
    }
}
