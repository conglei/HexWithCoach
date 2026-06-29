//
//  MacCoachPreferences.swift
//  VocoEngine (compiled into the macOS VocoMac module)
//
//  BYOK + opt-in state for the macOS Coach v2 driver (MC-R4). Deliberately a
//  macOS-local mirror of iOS's `Voco/CoachPreferences.swift` rather than a shared
//  move: it reads/writes the *same* App Group `UserDefaults` keys and the *same*
//  `CoachKeychain` account, so both platforms observe identical opt-in / autoLLM /
//  L1 / BYOK-key state without entangling the iOS app's `CoachPreferences` (which
//  carries iOS-only onboarding wiring on `origin/main` and is a merge hot spot).
//
//  Keys are kept byte-for-byte identical to iOS (`hex.coach.*`) so a single App
//  Group bucket backs both apps. The Gemini key lives only in the device Keychain
//  via `CoachKeychain` (never synced). AppKit-free — Foundation + VocoCore only.
//

import Foundation
import VocoCore
import Observation

@MainActor
@Observable
final class MacCoachPreferences {
    private let defaults = UserDefaults(suiteName: HexAppGroup.identifier) ?? .standard
    // Identical to iOS `CoachPreferences` so both apps share the same bucket.
    @ObservationIgnored private static let enabledKey = "hex.coach.enabled"
    @ObservationIgnored private static let firstLanguageKey = "hex.coach.firstLanguage"
    @ObservationIgnored private static let autoLLMKey = "hex.coach.autoLLM"

    /// User opted the Coach in. Gated on having a key to actually run (see `isReady`).
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    /// Whether the paid LLM lane runs automatically over the backlog. Defaults ON
    /// (mirrors iOS): a user who pasted a key + opted in wants coaching to "just
    /// appear", bounded by the monthly budget cap. Free objective analysis is
    /// unaffected (always on); this gates only LLM spend.
    var autoLLM: Bool {
        didSet { defaults.set(autoLLM, forKey: Self.autoLLMKey) }
    }

    /// The learner's first language (L1), a keyless pronunciation prioritization
    /// prior. `nil` means unknown; it never gates coaching. Shared with iOS via the
    /// App Group key.
    var firstLanguage: String? {
        didSet {
            let trimmed = firstLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                defaults.set(trimmed, forKey: Self.firstLanguageKey)
            } else {
                defaults.removeObject(forKey: Self.firstLanguageKey)
            }
        }
    }

    /// Whether a BYOK Gemini key is currently stored in this device's Keychain.
    private(set) var hasAPIKey: Bool

    /// The Coach can actually run the LLM lane only when opted in *and* a key is present.
    var isReady: Bool { enabled && hasAPIKey }

    init() {
        enabled = defaults.bool(forKey: Self.enabledKey)
        hasAPIKey = (CoachKeychain.read(CoachKeychain.geminiAPIKeyAccount)?.isEmpty == false)
        firstLanguage = defaults.string(forKey: Self.firstLanguageKey)
        // Default ON when never set (matches iOS): `object(forKey:)` distinguishes
        // "unset" from a stored `false` so an explicit opt-out survives relaunches.
        autoLLM = defaults.object(forKey: Self.autoLLMKey) as? Bool ?? true
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
