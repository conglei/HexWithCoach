//
//  WaveformView.swift
//  HexIOSKeyboard
//
//  A lightweight, purely-decorative waveform shown while capturing. The keyboard
//  extension cannot read live mic levels (the host app holds the mic), so this is
//  a synthesized animation — it only signals "we're listening", never real audio.
//

import SwiftUI

struct WaveformView: View {
    /// When false the bars rest at a calm baseline (no animation churn).
    var isActive: Bool
    /// Bar color. Defaults to the accent; pass `.white` on a colored pill so the
    /// bars don't clash with the fill.
    var tint: Color = .accentColor
    /// Bar width/height scale. The toolbar uses a compact variant.
    var barWidth: CGFloat = 4
    var maxHeight: CGFloat = 34

    private let barCount = 13

    var body: some View {
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
