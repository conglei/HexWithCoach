//
//  WaveformView.swift
//  HexIOSKeyboard
//
//  The waveform shown on the recording pill while capturing. The keyboard can't
//  read the mic itself, but during a Flow Session the host streams the live input
//  level across the App Group (see KeyboardAudioMeter); when those `levels` arrive
//  they drive a *real* waveform. Until the first sample lands we fall back to a
//  synthesized animation so the strip is never empty.
//

import SwiftUI

struct WaveformView: View {
    /// When false the bars rest at a calm baseline (no animation churn).
    var isActive: Bool
    /// Bar color. Defaults to the brand orange accent (#ea580c); pass `.white` on a
    /// colored pill so the bars don't clash with the fill.
    var tint: Color = Color(red: 0.918, green: 0.345, blue: 0.047)
    /// Bar width/height scale. The toolbar uses a compact variant.
    var barWidth: CGFloat = 4
    var maxHeight: CGFloat = 34
    /// Live mic levels (0…1) streamed from the host, newest last. When non-empty
    /// these draw the real waveform; empty falls back to the synthesized motion.
    var levels: [CGFloat] = []

    private let barCount = 13

    var body: some View {
        if levels.isEmpty {
            synthesized
        } else {
            live
        }
    }

    /// The real waveform: one bar per streamed level.
    private var live: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(tint)
                    .frame(width: barWidth, height: barHeight(for: level))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.06), value: levels)
        .accessibilityHidden(true)
    }

    /// Fallback motion shown until the first live level arrives.
    private var synthesized: some View {
        TimelineView(.animation(minimumInterval: isActive ? 1.0 / 30.0 : nil, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    Capsule()
                        .fill(isActive ? tint : tint.opacity(0.4))
                        .frame(width: barWidth, height: barHeight(index: index, time: t))
                }
            }
            .frame(height: maxHeight)
            .animation(.easeInOut(duration: 0.08), value: t)
        }
        .accessibilityHidden(true)
    }

    /// Map a 0…1 level to a bar height with a visible floor.
    private func barHeight(for level: CGFloat) -> CGFloat {
        let minBar = maxHeight * 0.22
        return minBar + max(0, min(1, level)) * (maxHeight - minBar)
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let minBar = maxHeight * 0.22
        guard isActive else { return minBar }
        // Each bar gets its own phase + speed so the wave looks organic.
        let speed = 4.0 + Double(index % 4)
        let offset = Double(index) * 0.6
        let wave = sin(time * speed + offset)
        let normalized = (wave + 1) / 2 // 0...1
        return minBar + CGFloat(normalized) * (maxHeight - minBar)
    }
}
