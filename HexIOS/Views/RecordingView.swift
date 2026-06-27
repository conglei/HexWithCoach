//
//  RecordingView.swift
//  HexIOS
//
//  Recording modal: presented over Home while capturing an in-app note. Top bar
//  (Cancel · timer · language), a LISTENING state with a gradient waveform, and a
//  gradient stop button. Styled with HexTheme.
//

import SwiftUI

struct RecordingView: View {
    let model: DictationModel
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Spacer()

            if model.phase == .transcribing {
                transcribing
            } else {
                listening
            }

            Spacer()

            if model.phase != .transcribing {
                stopButton.padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { v in dragOffset = min(0, v.translation.height) }
                .onEnded { v in
                    if v.translation.height < -80 { model.cancelRecording() }
                    withAnimation(.snappy) { dragOffset = 0 }
                }
        )
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { model.cancelRecording() }
                .foregroundStyle(.secondary)
            Spacer()
            timerPill
            Spacer()
            Text("EN")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HexTheme.gradientColors[0])
        }
    }

    private var timerPill: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 7) {
                Circle().fill(HexTheme.gradient).frame(width: 8, height: 8)
                Text(elapsedString).monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground), in: .capsule)
        }
    }

    private var elapsedString: String {
        let start = model.recordingStartedAt ?? Date()
        let secs = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private var listening: some View {
        VStack(spacing: 28) {
            HStack(spacing: 7) {
                Circle().fill(HexTheme.gradient).frame(width: 8, height: 8)
                Text("LISTENING")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(HexTheme.gradientColors[0])
            }
            waveform
            Text("Tap to stop · swipe up to cancel")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var waveform: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(HexTheme.gradient)
                    .frame(width: 4, height: 8 + level * 56)
            }
        }
        .frame(height: 70)
        .animation(.linear(duration: 0.05), value: model.levels)
    }

    private var stopButton: some View {
        Button {
            Task { await model.toggleRecording() }
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(HexTheme.gradient, in: .circle)
                .shadow(color: HexTheme.gradientColors[1].opacity(0.35), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var transcribing: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Transcribing…").foregroundStyle(.secondary)
        }
    }
}
