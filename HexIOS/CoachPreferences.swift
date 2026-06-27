//
//  CoachPreferences.swift
//  HexIOS
//
//  BYOK + opt-in state for the Coach (CE-1). The Coach is OFF by default and only
//  ever uploads speech to a cloud LLM once the user explicitly opts in *and*
//  supplies their own Gemini API key. The opt-in flag lives in the shared App
//  Group (so the keyboard could later reflect coach state); the API key lives in
//  the device Keychain via CoachKeychain (never synced).
//

import Foundation
import HexCore
import Observation

@MainActor
@Observable
final class CoachPreferences {
    private let defaults = UserDefaults(suiteName: HexAppGroup.identifier) ?? .standard
    @ObservationIgnored private static let enabledKey = "hex.coach.enabled"

    /// User opted the Coach in. Gated on having a key to actually run (see `isReady`).
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    /// Whether a BYOK Gemini key is currently stored.
    private(set) var hasAPIKey: Bool

    /// The Coach can actually analyze only when opted in *and* a key is present.
    var isReady: Bool { enabled && hasAPIKey }

    init() {
        enabled = defaults.bool(forKey: Self.enabledKey)
        hasAPIKey = (CoachKeychain.read(CoachKeychain.geminiAPIKeyAccount)?.isEmpty == false)
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        CoachKeychain.write(CoachKeychain.geminiAPIKeyAccount, trimmed)
        hasAPIKey = true
    }

    func clearAPIKey() {
        CoachKeychain.delete(CoachKeychain.geminiAPIKeyAccount)
        hasAPIKey = false
    }
}
