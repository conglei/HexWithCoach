//
//  KeyboardView.swift
//  HexIOSKeyboard
//
//  The keyboard's SwiftUI root. The keys are rendered by KeyboardKit's native
//  `KeyboardView` (a system-matching QWERTY with shift/caps/number layers, the
//  globe key, magnification, dark mode, per-device metrics — all the things we
//  used to hand-build and could never get pixel-perfect). We only replace its
//  toolbar slot with the Hex dictation strip (`HexToolbar`).
//
//  KeyboardKit handles all typing through the text document proxy itself; the
//  controller no longer wires insert/delete/space/return. See
//  `KeyboardViewController` for the dictation/IPC engine that remains ours.
//
//  Type is named `HexKeyboardRootView` (not `KeyboardView`) to avoid colliding
//  with KeyboardKit's own `KeyboardView`.
//

import KeyboardKit
import SwiftUI

/// The hosted SwiftUI surface, built by `KeyboardViewController` inside
/// `setupKeyboardView { ... }`. It receives KeyboardKit's observable `state`
/// (for the keys) plus our `hexState` / `actions` (for the dictation strip).
struct HexKeyboardRootView: View {
    /// KeyboardKit's observable keyboard state, from `controller.state`.
    let keyboardState: Keyboard.State
    /// KeyboardKit's services, from `controller.services`.
    let services: Keyboard.Services
    /// Hex's own dictation state machine (drives the toolbar).
    let hexState: KeyboardState
    /// Hex toolbar callbacks (mic / cancel / settings).
    let actions: KeyboardActions

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        KeyboardView(
            layout: KeyboardLayout.standard(for: keyboardState.keyboardContext),
            services: services,
            buttonContent: { $0.view },     // default key label
            buttonView: { $0.view },        // default key button
            collapsedView: { $0.view },     // default collapsed view
            emojiKeyboard: { $0.view },     // default emoji keyboard (placeholder w/o Pro)
            toolbar: { _ in                 // ← replace the autocomplete bar with Hex's strip
                HexToolbar(
                    state: hexState,
                    actions: actions,
                    colorScheme: colorScheme
                )
            }
        )
    }
}
