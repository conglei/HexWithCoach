//
//  QwertyKeyboardView.swift
//  HexIOSKeyboard
//
//  The Hex dictation toolbar strip that sits *above* the keys. The keys
//  themselves are now rendered natively by KeyboardKit's `KeyboardView` (see
//  `KeyboardView.swift` → `HexKeyboardRootView`); this file only owns the
//  Hex-specific surface that KeyboardKit doesn't provide:
//
//    • Idle:      big blue "Tap to dictate" pill · settings icon
//    • Recording: "Cancel" · big red "Tap to stop" pill (with live waveform)
//
//  The globe / next-keyboard key now lives on KeyboardKit's keyboard, so it's no
//  longer duplicated here. All text/IPC wiring stays in `KeyboardViewController`.
//
//  (Filename retained to avoid an Xcode project edit; the old hand-built QWERTY
//  layout it used to hold has been replaced by KeyboardKit.)
//

import SwiftUI

// MARK: - Hex toolbar (above the keys)

struct HexToolbar: View {
    let state: KeyboardState
    let actions: KeyboardActions
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 8) {
            if state.isCapturing {
                recordingControls
            } else {
                idleControls
            }
        }
        .frame(height: toolbarHeight)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // Idle: "Tap to dictate" · settings
    @ViewBuilder
    private var idleControls: some View {
        ToolbarPill(
            title: state.hasFullAccess ? "Tap to dictate" : "Enable Full Access to dictate",
            imageName: "DictateGlyph",
            fill: state.hasFullAccess ? AnyShapeStyle(KeyStyle.brandGradient) : AnyShapeStyle(Color.gray),
            enabled: state.hasFullAccess,
            glow: state.hasFullAccess ? KeyStyle.brand[1].opacity(0.32) : .clear,
            action: actions.onMic
        )

        ToolbarIconButton(systemImage: "slider.horizontal.3", colorScheme: colorScheme, action: actions.onSettings)
    }

    // Recording: Cancel · "Tap to stop"
    @ViewBuilder
    private var recordingControls: some View {
        ToolbarTextButton(title: "Cancel", colorScheme: colorScheme, action: actions.onCancelDictation)

        ToolbarPill(
            title: "Tap to stop",
            fill: AnyShapeStyle(KeyStyle.recordGradient),
            enabled: true,
            glow: KeyStyle.recordPink.opacity(0.30),
            leading: { AnyView(
                WaveformView(isActive: true, tint: .white, barWidth: 2.5, maxHeight: 18, levels: state.levels)
                    .fixedSize()
            ) },
            action: actions.onMic
        )
    }
}

// MARK: - Toolbar components

/// The big center pill ("Tap to dictate" / "Tap to stop"). Fills the available
/// width between the flanking buttons.
private struct ToolbarPill: View {
    let title: String
    var systemImage: String? = nil
    /// Name of a template asset (in the keyboard's asset catalog) to use as the
    /// leading glyph, e.g. the Hex dictation mark. Tinted white like `systemImage`.
    var imageName: String? = nil
    let fill: AnyShapeStyle
    let enabled: Bool
    var glow: Color = .clear
    var leading: () -> AnyView = { AnyView(EmptyView()) }
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        imageName: String? = nil,
        fill: AnyShapeStyle,
        enabled: Bool,
        glow: Color = .clear,
        leading: @escaping () -> AnyView = { AnyView(EmptyView()) },
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.imageName = imageName
        self.fill = fill
        self.enabled = enabled
        self.glow = glow
        self.leading = leading
        self.action = action
    }

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let imageName {
                    Image(imageName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                leading()
                Text(title).font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: toolbarHeight)
            .background(Capsule(style: .continuous).fill(fill))
            .shadow(color: glow, radius: 8, y: 3)
            .scaleEffect(isPressed ? 0.98 : 1)
            .opacity(isPressed ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeOut(duration: 0.05), value: isPressed)
    }
}

/// A square icon button (settings) flanking the pill.
private struct ToolbarIconButton: View {
    let systemImage: String
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(KeyStyle.neutralText(colorScheme))
                .frame(width: 46, height: toolbarHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(KeyStyle.neutralFill(colorScheme))
                )
        }
        .buttonStyle(.plain)
    }
}

/// A text button (Cancel) flanking the recording pill — sized to its label.
private struct ToolbarTextButton: View {
    let title: String
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(KeyStyle.neutralText(colorScheme))
                .padding(.horizontal, 18)
                .frame(height: toolbarHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(KeyStyle.neutralFill(colorScheme))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared style

/// Height of the Hex toolbar strip and its controls.
private let toolbarHeight: CGFloat = 42

private enum KeyStyle {
    /// Voco brand gradient — matches the app's primary buttons (HexTheme): a subtle
    /// same-hue burnt orange (#ea580c, top-leading) → brighter orange (bottom-trailing).
    /// Defined locally because the keyboard extension can't import the app target's HexTheme.
    static let brand = [
        Color(red: 0.918, green: 0.345, blue: 0.047),
        Color(red: 0.976, green: 0.451, blue: 0.086),
    ]
    static let brandGradient = LinearGradient(
        colors: brand, startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Recording pill — a clean red→pink, not the old muddy brick.
    static let recordPink = Color(red: 0.88, green: 0.21, blue: 0.42)
    static let recordGradient = LinearGradient(
        colors: [Color(red: 0.94, green: 0.27, blue: 0.36), recordPink],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Quiet, light neutral for the flanking buttons (settings / Cancel) — lighter and
    /// cleaner than a system special key so the gradient pill stays the hero.
    static func neutralFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.26, green: 0.26, blue: 0.28)
            : Color(red: 0.925, green: 0.933, blue: 0.945)
    }
    static func neutralText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.29, green: 0.31, blue: 0.34)
    }
}
