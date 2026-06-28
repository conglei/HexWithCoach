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
            systemImage: "mic.fill",
            fill: state.hasFullAccess ? Color.accentColor : Color.gray,
            enabled: state.hasFullAccess,
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
            fill: KeyStyle.recordRed,
            enabled: true,
            leading: { AnyView(
                WaveformView(isActive: true, tint: .white, barWidth: 2.5, maxHeight: 18)
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
    let fill: Color
    let enabled: Bool
    var leading: () -> AnyView = { AnyView(EmptyView()) }
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        fill: Color,
        enabled: Bool,
        leading: @escaping () -> AnyView = { AnyView(EmptyView()) },
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.fill = fill
        self.enabled = enabled
        self.leading = leading
        self.action = action
    }

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                leading()
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: toolbarHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill)
            )
            .scaleEffect(isPressed ? 0.98 : 1)
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
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: 44, height: toolbarHeight)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KeyStyle.specialFill(colorScheme))
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
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .padding(.horizontal, 18)
                .frame(height: toolbarHeight)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KeyStyle.specialFill(colorScheme))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared style

/// Height of the Hex toolbar strip and its controls.
private let toolbarHeight: CGFloat = 40

private enum KeyStyle {
    /// Neutral fill for the flanking toolbar buttons — close to a system special key.
    static func specialFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.20, green: 0.20, blue: 0.22)
            : Color(red: 0.68, green: 0.70, blue: 0.73)
    }

    /// Recording pill — a softened red, not the alarming system candy red.
    static let recordRed = Color(red: 0.83, green: 0.31, blue: 0.29)
}
