//
//  CapturePreferences.swift
//  HexIOS
//
//  Privacy / capture controls (RC-8). Capture is local by default; analysis is
//  opt-in + BYOK (CoachPreferences). Incognito is a "don't save this" mode:
//  dictation still inserts text, but nothing is retained to history or the Coach
//  corpus. Stored in the App Group so the keyboard side can read/set it too.
//

import Foundation
import HexCore

enum CapturePreferences {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: HexAppGroup.identifier) }

    /// When on, no transcript or audio is retained from dictation.
    static var incognito: Bool {
        get { defaults?.bool(forKey: Self.incognitoKey) ?? false }
        set { defaults?.set(newValue, forKey: Self.incognitoKey) }
    }

    static let incognitoKey = "hex.capture.incognito"
}
