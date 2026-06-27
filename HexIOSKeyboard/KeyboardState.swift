//
//  KeyboardState.swift
//  HexIOSKeyboard
//
//  The keyboard's state machine — split out from the SwiftUI view so it carries
//  no UIKit/SwiftUI dependency and can be compiled directly into a unit-test
//  bundle (app-extension modules aren't linkable from a test target). Pure
//  `Observation` + Foundation.
//
//    • `KeyboardPhase`   — the six deliberate states (idle / recording / …).
//    • `KeyboardState`   — observable model derived into `phase`.
//    • `KeyboardActions` — callbacks back into `KeyboardViewController`'s text/IPC
//      wiring (insert / delete / space / return / globe / mic / …).
//

import Foundation
import Observation

/// The six keyboard states from design §5. The view derives its appearance from
/// this rather than from scattered booleans, so every state renders deliberately.
enum KeyboardPhase: Equatable {
    case noFullAccess
    case idle
    case recording
    case inserting
    case needsBounce
    case error(String)
}

@MainActor
@Observable
final class KeyboardState {
    var statusText: String = "Tap to dictate"
    var needsNextKeyboard: Bool = false
    var hasFullAccess: Bool = true
    /// A continuous Flow Session is active (dictate in place, no bounce).
    var sessionActive: Bool = false
    /// Currently capturing an utterance (mic is hot in the host app).
    var isCapturing: Bool = false
    /// When the active Flow Session expires (drives the "MM:SS left" countdown).
    var sessionExpiresAt: Date? = nil
    /// Brief confirmation flag after a successful insert (the "inserting" state).
    var justInserted: Bool = false
    /// Set when the host app/model is unreachable; surfaces the error state.
    var errorMessage: String? = nil

    /// Ticks once per second so the countdown pill re-renders; the view binds to
    /// this so SwiftUI recomputes `remaining` without us threading a Timer in.
    var clock: Date = Date()

    /// The single source of truth for which of the six states we're in.
    var phase: KeyboardPhase {
        if !hasFullAccess { return .noFullAccess }
        if let errorMessage { return .error(errorMessage) }
        if isCapturing { return .recording }
        if justInserted { return .inserting }
        // A session that was active but is no longer usable needs a re-bounce.
        if sessionActive, let expiresAt = sessionExpiresAt, clock >= expiresAt {
            return .needsBounce
        }
        return .idle
    }

    /// Seconds remaining in the active session, or nil when there is no live
    /// countdown to show.
    var remaining: TimeInterval? {
        guard sessionActive, let expiresAt = sessionExpiresAt else { return nil }
        let secs = expiresAt.timeIntervalSince(clock)
        return secs > 0 ? secs : nil
    }

    /// "MM:SS" formatting for the session pill.
    var remainingText: String? {
        guard let remaining else { return nil }
        let total = Int(remaining.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Actions the SwiftUI surface hands back to `KeyboardViewController`, which owns
/// all the `textDocumentProxy` / IPC wiring.
struct KeyboardActions {
    var onMic: () -> Void
    var onDelete: () -> Void
    var onNextKeyboard: () -> Void
    var onSpace: () -> Void
    var onReturn: () -> Void
    var onDeleteWord: () -> Void
    var onCaretMove: (Int) -> Void
    var onInsert: (String) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    /// Cancel the in-progress dictation (toolbar "Cancel"). Currently stops the
    /// capture like the mic does; true discard isn't wired yet.
    var onCancelDictation: () -> Void
    /// Open the Hex app (toolbar settings icon) for preferences/onboarding.
    var onSettings: () -> Void
}
