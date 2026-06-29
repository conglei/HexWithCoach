//
//  RecordingView.swift
//  HexIOS
//
//  Recording modal: presented over Home while capturing an in-app note. Top bar
//  (Cancel · timer · language), a LISTENING/PAUSED state with a gradient waveform,
//  and a Pause/Resume + Done control pair. Pausing keeps the note open (and saves
//  the audio so far) so the user can resume and add more; Done finalizes it.
//

import SwiftUI

struct RecordingView: View {
    let model: DictationModel

    private var isPaused: Bool { model.phase == .paused }

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
                controls.padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.18), value: model.phase)
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
                Circle()
                    .fill(isPaused ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(HexTheme.gradient))
                    .frame(width: 8, height: 8)
                Text(elapsedString).monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground), in: .capsule)
        }
    }

    private var elapsedString: String {
        let secs = max(0, Int(model.currentElapsed))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private var listening: some View {
        VStack(spacing: 28) {
            HStack(spacing: 7) {
                Circle()
                    .fill(isPaused ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(HexTheme.gradient))
                    .frame(width: 8, height: 8)
                Text(isPaused ? "PAUSED" : "LISTENING")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(isPaused ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(HexTheme.gradientColors[0]))
            }
            waveform
                .opacity(isPaused ? 0.3 : 1)
            Text(isPaused ? "Paused · resume to keep dictating" : "Pause to take a break, Done when finished")
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

    private var controls: some View {
        HStack(spacing: 40) {
            // Pause / Resume — keeps the note open so the user can add more later.
            Button {
                if isPaused { model.resumeRecording() } else { model.pauseRecording() }
            } label: {
                Image(systemName: isPaused ? "mic.fill" : "pause.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(HexTheme.gradientColors[0])
                    .frame(width: 68, height: 68)
                    .background(Color(.secondarySystemGroupedBackground), in: .circle)
                    .overlay(Circle().strokeBorder(HexTheme.gradientColors[0].opacity(0.35), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused ? "Resume" : "Pause")

            // Done — finalize and transcribe the note.
            Button {
                Task { await model.finishRecording() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(HexTheme.gradient, in: .circle)
                    .shadow(color: HexTheme.gradientColors[1].opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
    }

    private var transcribing: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Transcribing…").foregroundStyle(.secondary)
        }
    }
}
