//
//  KeyboardView.swift
//  HexIOSKeyboard
//
//  The keyboard's SwiftUI entry point. It clones Apple's standard QWERTY layout
//  (see `QwertyKeyboardView`) and drops the Hex dictation mic into the bottom-right
//  corner, where Apple's dictation mic normally lives. There is no prediction/
//  autocorrect bar — a third-party extension doesn't get Apple's language model.
//
//  The state machine it renders (`KeyboardPhase` / `KeyboardState` / `KeyboardActions`)
//  lives in `KeyboardState.swift` so it can be unit-tested without UIKit.
//

import SwiftUI

/// The hosted SwiftUI surface. `KeyboardViewController` constructs this with the
/// shared `state` + `actions`; the entry signature `KeyboardView(state:actions:)`
/// is part of the controller contract and must stay stable.
struct KeyboardView: View {
    let state: KeyboardState
    let actions: KeyboardActions

    var body: some View {
        QwertyKeyboardView(state: state, actions: actions)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
