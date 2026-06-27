//
//  QwertyKeyboardView.swift
//  HexIOSKeyboard
//
//  A standard QWERTY layout that clones Apple's system keyboard, with a Hex
//  toolbar strip *above* the keys instead of a corner dictation mic. The strip is
//  the only Hex-specific surface:
//
//    • Idle:      [globe] · big blue "Tap to dictate" pill · settings icon
//    • Recording: "Cancel" · big red "Tap to stop" pill (the keys dim underneath)
//
//  We intentionally drop the system dictation mic (bottom-right) and surface our
//  own dictation control on top, where it's unmissable. There is no prediction/
//  autocorrect bar — a third-party extension doesn't get Apple's language model.
//
//  All text/IPC wiring stays in `KeyboardViewController`; this view just renders
//  `KeyboardState` and calls back through `KeyboardActions`.
//

import SwiftUI

// MARK: - Layout model

/// A single key in a row. Most keys are letters; a few are "special" (shift,
/// backspace, etc.) and carry their own glyph + width weight.
private enum KeyKind: Equatable {
    case character(String)
    case shift
    case backspace
    case modeSwitch(String)   // "123" / "ABC" / "#+="
    case space
    case `return`

    var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }

    /// For non-character keys: how the leftover row width (after the fixed-width
    /// letters) is shared. Letters always take the same `letterW`, so they line
    /// up across rows and shorter rows (a-l) inset — exactly like iOS.
    var fillWeight: CGFloat {
        switch self {
        case .character: return 0
        case .space: return 5
        case .shift, .backspace, .modeSwitch, .return: return 1
        }
    }
}

// MARK: - Shift / letter case state

private enum ShiftState: Equatable {
    case lowercase
    case shifted     // one-shot: reverts to lowercase after the next letter
    case capsLock

    var isUppercase: Bool { self != .lowercase }
}

private enum KeyboardLayer: Equatable {
    case letters
    case numbers      // 123
    case symbols      // #+=
}

struct QwertyKeyboardView: View {
    let state: KeyboardState
    let actions: KeyboardActions

    @Environment(\.colorScheme) private var colorScheme

    @State private var shift: ShiftState = .lowercase
    @State private var layer: KeyboardLayer = .letters

    var body: some View {
        ZStack(alignment: .top) {
            keyboardBackground.ignoresSafeArea()

            VStack(spacing: 6) {
                HexToolbar(
                    state: state,
                    actions: actions,
                    colorScheme: colorScheme
                )

                statusBanner

                keysSurface
                    .opacity(keysDimmed ? 0.35 : 1)
                    .allowsHitTesting(!keysDisabled)
            }
            .padding(.horizontal, 3)
            .padding(.top, 4)
            .padding(.bottom, 3)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.easeInOut(duration: 0.15), value: state.isCapturing)
        .animation(.easeInOut(duration: 0.12), value: layer)
    }

    // MARK: - Background

    private var keyboardBackground: Color {
        // Matches the system keyboard's recessed tray color closely enough for a
        // third-party extension (we can't read the true system material). Dark
        // mode is near-black like Apple's, so the keys read as raised.
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.09, blue: 0.10)
            : Color(red: 0.82, green: 0.83, blue: 0.85)
    }

    /// Keys dim while recording (the host app holds the mic) and when Full Access
    /// is off (the toolbar pill is the only useful control then).
    private var keysDimmed: Bool { state.isCapturing || !state.hasFullAccess }
    private var keysDisabled: Bool { state.isCapturing || !state.hasFullAccess }

    // MARK: - Status banner (non-recording phases)

    @ViewBuilder
    private var statusBanner: some View {
        switch state.phase {
        case .noFullAccess:
            banner(text: "Enable Full Access in Settings ▸ Keyboards",
                   systemImage: "exclamationmark.lock.fill",
                   tint: .orange)
        case .error(let message):
            banner(text: message,
                   systemImage: "exclamationmark.triangle.fill",
                   tint: .red)
        // `.inserting` deliberately shows nothing — the dictated text appearing in
        // the host app is its own confirmation; a toast on top is noise.
        case .idle, .recording, .inserting, .needsBounce:
            EmptyView()
        }
    }

    private func banner(text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .padding(.horizontal, 3)
    }

    // MARK: - Keys surface

    private var keysSurface: some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                KeyRow(
                    keys: row,
                    shift: shift,
                    layer: layer,
                    colorScheme: colorScheme,
                    onCharacter: handleCharacter,
                    onShift: handleShift,
                    onBackspace: { actions.onDelete() },
                    onModeSwitch: handleModeSwitch,
                    onSpace: { actions.onSpace() },
                    onReturn: { actions.onReturn() }
                )
            }
        }
    }

    private let rowSpacing: CGFloat = 11

    // MARK: - Row definitions per layer

    private var rows: [[KeyKind]] {
        switch layer {
        case .letters:
            return [
                "qwertyuiop".map { .character(String($0)) },
                "asdfghjkl".map { .character(String($0)) },
                [.shift] + "zxcvbnm".map { .character(String($0)) } + [.backspace],
                bottomRow,
            ]
        case .numbers:
            return [
                "1234567890".map { .character(String($0)) },
                "-/:;()$&@\"".map { .character(String($0)) },
                [.modeSwitch("#+=")] + ".,?!'".map { .character(String($0)) } + [.backspace],
                bottomRow,
            ]
        case .symbols:
            return [
                "[]{}#%^*+=".map { .character(String($0)) },
                "_\\|~<>€£¥•".map { .character(String($0)) },
                [.modeSwitch("123")] + ".,?!'".map { .character(String($0)) } + [.backspace],
                bottomRow,
            ]
        }
    }

    /// Bottom row: mode-switch · space · return. The globe lives in the top
    /// toolbar now, and there is no corner mic.
    private var bottomRow: [KeyKind] {
        [.modeSwitch(layer == .letters ? "123" : "ABC"), .space, .return]
    }

    // MARK: - Handlers

    private func handleCharacter(_ raw: String) {
        let text: String
        if layer == .letters {
            text = shift.isUppercase ? raw.uppercased() : raw
        } else {
            text = raw
        }
        actions.onInsert(text)
        // One-shot shift reverts after a single letter (caps-lock persists).
        if shift == .shifted { shift = .lowercase }
    }

    private func handleShift() {
        switch shift {
        case .lowercase: shift = .shifted
        case .shifted: shift = .capsLock      // tap again → caps lock
        case .capsLock: shift = .lowercase
        }
    }

    private func handleModeSwitch(_ label: String) {
        switch label {
        case "123": layer = .numbers
        case "ABC": layer = .letters
        case "#+=": layer = .symbols
        default: break
        }
    }
}

// MARK: - Hex toolbar (above the keys)

private struct HexToolbar: View {
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
        .padding(.horizontal, 3)
    }

    // Idle: globe · "Tap to dictate" · settings
    @ViewBuilder
    private var idleControls: some View {
        if state.needsNextKeyboard {
            ToolbarIconButton(systemImage: "globe", colorScheme: colorScheme, action: actions.onNextKeyboard)
        }

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

/// A square icon button (globe / settings) flanking the pill.
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

// MARK: - Key row (proportional widths)

private struct KeyRow: View {
    let keys: [KeyKind]
    let shift: ShiftState
    let layer: KeyboardLayer
    let colorScheme: ColorScheme

    let onCharacter: (String) -> Void
    let onShift: () -> Void
    let onBackspace: () -> Void
    let onModeSwitch: (String) -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void

    private let keySpacing: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let widths = keyWidths(totalWidth: geo.size.width)
            HStack(spacing: keySpacing) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    keyButton(for: key)
                        .frame(width: widths[index])
                }
            }
            // Center so letter-only rows (a-l, number rows) inset like Apple's.
            .frame(width: geo.size.width, height: keyHeight, alignment: .center)
        }
        .frame(height: keyHeight)
    }

    /// iOS-style widths: every letter key is the same width, derived from a
    /// 10-column grid (the widest row). Special keys expand to absorb the leftover
    /// so full rows span the width; shorter letter-only rows end up narrower and
    /// are centered — the inset that makes a-l read like Apple's keyboard.
    private func keyWidths(totalWidth: CGFloat) -> [CGFloat] {
        let g = keySpacing
        let letterW = max((totalWidth - 9 * g) / 10, 0)
        let charCount = keys.filter(\.isCharacter).count
        let gaps = CGFloat(max(keys.count - 1, 0)) * g
        let remaining = max(totalWidth - CGFloat(charCount) * letterW - gaps, 0)
        let sumFill = keys.map(\.fillWeight).reduce(0, +)
        return keys.map { key in
            if key.isCharacter { return letterW }
            guard sumFill > 0 else { return letterW }
            return remaining * key.fillWeight / sumFill
        }
    }

    @ViewBuilder
    private func keyButton(for key: KeyKind) -> some View {
        switch key {
        case .character(let c):
            let display = (layer == .letters && shift.isUppercase) ? c.uppercased() : c
            LetterKey(label: display, colorScheme: colorScheme) {
                onCharacter(c)
            }
        case .shift:
            SpecialKey(colorScheme: colorScheme, emphasized: shift != .lowercase) {
                onShift()
            } content: {
                Image(systemName: shiftGlyph)
                    .font(.system(size: 17, weight: .regular))
            }
        case .backspace:
            SpecialKey(colorScheme: colorScheme) { onBackspace() } content: {
                Image(systemName: "delete.left")
                    .font(.system(size: 17, weight: .regular))
            }
        case .modeSwitch(let label):
            SpecialKey(colorScheme: colorScheme) { onModeSwitch(label) } content: {
                Text(label)
                    .font(.system(size: 15, weight: .regular))
            }
        case .space:
            SpecialKey(colorScheme: colorScheme, light: true) { onSpace() } content: {
                Text("space")
                    .font(.system(size: 15, weight: .regular))
            }
        case .return:
            SpecialKey(colorScheme: colorScheme) { onReturn() } content: {
                Text("return")
                    .font(.system(size: 15, weight: .regular))
            }
        }
    }

    private var shiftGlyph: String {
        switch shift {
        case .lowercase: return "shift"
        case .shifted: return "shift.fill"
        case .capsLock: return "capslock.fill"
        }
    }
}

// MARK: - Individual key views

private let keyHeight: CGFloat = 46
private let keyCornerRadius: CGFloat = 7
/// Height of the Hex toolbar strip and its controls — slim, so the strip reads
/// as a refined accessory rather than a giant slab over the keys.
private let toolbarHeight: CGFloat = 40

private struct LetterKey: View {
    let label: String
    let colorScheme: ColorScheme
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Text(label)
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: keyHeight)
            .background(
                RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
                    .fill(KeyStyle.letterFill(colorScheme))
                    .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: 1)
            )
            .overlay {
                // Press magnification bubble (nice-to-have).
                if isPressed {
                    MagnifyBubble(label: label, colorScheme: colorScheme)
                        .offset(y: -keyHeight)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.96 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { isPressed = true } }
                    .onEnded { _ in
                        isPressed = false
                        action()
                    }
            )
            .animation(.easeOut(duration: 0.05), value: isPressed)
    }
}

private struct MagnifyBubble: View {
    let label: String
    let colorScheme: ColorScheme

    var body: some View {
        Text(label)
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .frame(width: 46, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(KeyStyle.letterFill(colorScheme))
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
    }
}

private struct SpecialKey<Content: View>: View {
    let colorScheme: ColorScheme
    var emphasized: Bool = false
    var light: Bool = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isPressed = false

    init(
        colorScheme: ColorScheme,
        emphasized: Bool = false,
        light: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.colorScheme = colorScheme
        self.emphasized = emphasized
        self.light = light
        self.action = action
        self.content = content
    }

    var body: some View {
        content()
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: keyHeight)
            .background(
                RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
                    .fill(fill)
                    .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: 1)
            )
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.96 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { isPressed = true } }
                    .onEnded { _ in
                        isPressed = false
                        action()
                    }
            )
            .animation(.easeOut(duration: 0.05), value: isPressed)
    }

    private var fill: Color {
        if emphasized { return KeyStyle.emphasizedFill(colorScheme) }
        if light { return KeyStyle.letterFill(colorScheme) }
        return KeyStyle.specialFill(colorScheme)
    }
}

// MARK: - Shared key colors

private enum KeyStyle {
    static func letterFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.33, green: 0.33, blue: 0.35)
            : Color.white
    }

    static func specialFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.20, green: 0.20, blue: 0.22)
            : Color(red: 0.68, green: 0.70, blue: 0.73)
    }

    static func emphasizedFill(_ scheme: ColorScheme) -> Color {
        // Active shift / caps lock — lighter, like the system's highlighted shift.
        scheme == .dark
            ? Color(red: 0.55, green: 0.55, blue: 0.58)
            : Color.white
    }

    /// Recording pill — a softened red, not the alarming system candy red.
    static let recordRed = Color(red: 0.83, green: 0.31, blue: 0.29)
}
