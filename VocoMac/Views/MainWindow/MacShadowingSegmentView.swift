//
//  MacShadowingSegmentView.swift
//  VocoMac
//
//  MC-R9 — the native macOS shadowing UX for one practiced line, embedded in
//  `MacPracticeSessionView`. Mirrors the iOS `ShadowingView` flow ("Say it better /
//  Hear it / YOUR TURN") natively on macOS:
//
//    • A quoted target card with a "Hear it" (TTS) button.
//    • A mic hero with a record/stop button and a live level meter while recording.
//    • A result with the ASR match verdict (✓/✗), the heard transcript on a miss,
//      and — when the phoneme model is present — per-phoneme GOP deltas
//      (improved / still-weak). The GOP block is simply absent on the companion app.
//

import SwiftUI
import VocoCore

struct MacShadowingSegmentView: View {
    @Bindable var model: MacShadowingModel

    var body: some View {
        VStack(spacing: 20) {
            targetCard
            if model.phase == .scored {
                resultSection
            } else {
                micSection
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Target

    private var targetCard: some View {
        VStack(spacing: 14) {
            Text("“\(model.target)”")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)

            Button { model.speak() } label: {
                Label("Hear it", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .help("Hear the natural phrasing")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.4))
        )
    }

    // MARK: - Mic hero

    private var micSection: some View {
        VStack(spacing: 14) {
            Text("● YOUR TURN — SAY IT")
                .font(.caption.weight(.bold)).tracking(1)
                .foregroundStyle(.tint)

            Button {
                Task { await model.toggleRecord() }
            } label: {
                Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(model.phase == .recording ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tint), in: Circle())
            }
            .buttonStyle(.plain)
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

    /// A live level meter driven by the learner's actual mic input while recording.
    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.tint)
                    .frame(width: 3, height: 4 + level * 26)
            }
        }
        .frame(height: 30)
        .animation(.linear(duration: 0.05), value: model.levels)
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(spacing: 14) {
            verdictCard
            if let comparison = model.gopComparison, !comparison.isEmpty {
                gopCard(comparison)
            }
            Button {
                Task { await model.toggleRecord() }
            } label: {
                Label("Try again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var verdictCard: some View {
        VStack(spacing: 10) {
            Image(systemName: model.isSuccess ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(model.isSuccess ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.orange))
            Text(model.isSuccess ? "Nice — that matched" : "Good effort — give it another go")
                .font(.headline)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Image(systemName: model.isSuccess ? "text.bubble.fill" : "text.bubble")
                Text(model.isSuccess ? "Right words" : "Words off")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(model.isSuccess ? Color.green : Color.orange)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background((model.isSuccess ? Color.green : Color.orange).opacity(0.12), in: Capsule())

            if !model.heard.isEmpty, !model.isSuccess {
                Text("Heard: “\(model.heard)”")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.4))
        )
    }

    /// Per-phoneme GOP deltas vs. the previous attempt — present only when the
    /// phoneme model is installed (no-op on the companion app today).
    private func gopCard(_ comparison: ShadowingGOP.Comparison) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOUNDS")
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(.secondary)
            if !comparison.improved.isEmpty {
                phonemeRow(
                    icon: "arrow.up.right.circle.fill",
                    tint: .green,
                    label: "Improved",
                    symbols: comparison.improved.map(\.symbol)
                )
            }
            if !comparison.stillWeak.isEmpty {
                phonemeRow(
                    icon: "waveform.badge.exclamationmark",
                    tint: .orange,
                    label: "Keep working",
                    symbols: comparison.stillWeak.map(\.symbol)
                )
            }
            if comparison.improved.isEmpty, comparison.stillWeak.isEmpty {
                Text("Sounds steady — no big changes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.4))
        )
    }

    private func phonemeRow(icon: String, tint: Color, label: String, symbols: [String]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(label).font(.footnote.weight(.semibold))
            Text(symbols.prefix(4).map { "/\($0)/" }.joined(separator: " "))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
