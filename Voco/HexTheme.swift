//
//  HexTheme.swift
//  HexIOS
//
//  Shared visual language for the app refresh: a burnt-orange brand accent, a
//  white rounded-card surface, and a solid accent primary button. Used everywhere
//  so the screens feel like one polished product.
//

import SwiftUI

enum HexTheme {
    /// Primary brand accent — burnt orange (#ea580c).
    static let accent = Color(red: 0.918, green: 0.345, blue: 0.047)

    /// Brand accent stops. Both are the same orange hue (a subtle deepen→brighten);
    /// `gradientColors[0]` is the primary accent used as a solid color at call sites,
    /// `gradientColors[1]` is a slightly brighter orange used for accents/shadows.
    static let gradientColors = [
        accent,
        Color(red: 0.976, green: 0.451, blue: 0.086),
    ]

    /// Brand "gradient" — now a subtle same-hue orange (top-leading deeper → bottom-trailing brighter).
    static let gradient = LinearGradient(
        colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Soft tinted background for the gradient (cards, glow).
    static let gradientSoft = LinearGradient(
        colors: [gradientColors[0].opacity(0.12), gradientColors[1].opacity(0.12)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let cardRadius: CGFloat = 16
}

extension View {
    /// The standard white rounded-card surface.
    func hexCard(padding: CGFloat = 16, radius: CGFloat = HexTheme.cardRadius) -> some View {
        self
            .padding(padding)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}

/// Full-width gradient primary button ("Connect a key", "Say it better", "Done").
struct HexGradientButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(.white)
            .padding(.vertical, compact ? 10 : 14)
            .padding(.horizontal, compact ? 16 : 0)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(HexTheme.gradient, in: RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A circular gradient mic/record button — the hero control.
struct GradientMicButton: View {
    var systemImage: String = "mic.fill"
    var size: CGFloat = 140
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(HexTheme.gradient, in: .circle)
                .shadow(color: HexTheme.gradientColors[1].opacity(0.35), radius: 18, y: 10)
                .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .animation(.easeOut(duration: 0.1), value: pressed)
    }
}
