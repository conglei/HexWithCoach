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
import VocoCore
import Observation

@MainActor
@Observable
final class CoachPreferences {
    private let defaults = UserDefaults(suiteName: HexAppGroup.identifier) ?? .standard
    @ObservationIgnored private static let enabledKey = "hex.coach.enabled"
    @ObservationIgnored private static let firstLanguageKey = "hex.coach.firstLanguage"
    @ObservationIgnored private static let autoLLMKey = "hex.coach.autoLLM"

    /// User opted the Coach in. Gated on having a key to actually run (see `isReady`).
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    /// Whether the paid LLM lane runs **automatically** in the background over the
    /// backlog (CI-7 / ADR-0004). Defaults ON: a user who pasted a key + opted in
    /// wants coaching to "just appear" — but it stays hard-bounded by the monthly
    /// budget cap, and can be switched off here so spend happens only via the
    /// manual "Review now" override. Free objective analysis is unaffected (always
    /// on); this gates only LLM spend.
    var autoLLM: Bool {
        didSet { defaults.set(autoLLM, forKey: Self.autoLLMKey) }
    }

    /// The learner's first language (L1), asked once at onboarding (optional,
    /// skippable — ADR-0003). Used keyless as a pronunciation prioritization
    /// prior (see `L1InterferencePrior`). `nil` means unknown / "prefer not to
    /// say"; it never gates coaching. Stored here in the App Group rather than in
    /// LearnerProfile to keep this onboarding choice separate from the evolving,
    /// analysis-driven profile.
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

    /// Whether a BYOK Gemini key is currently stored.
    private(set) var hasAPIKey: Bool

    /// The Coach can actually analyze only when opted in *and* a key is present.
    var isReady: Bool { enabled && hasAPIKey }

    init() {
        enabled = defaults.bool(forKey: Self.enabledKey)
        hasAPIKey = (CoachKeychain.read(CoachKeychain.geminiAPIKeyAccount)?.isEmpty == false)
        firstLanguage = defaults.string(forKey: Self.firstLanguageKey)
        // Default ON when never set: automatic-batched LLM coaching is the new
        // primary path (CI-7). `object(forKey:)` distinguishes "unset" from a
        // stored `false` so an explicit opt-out survives relaunches.
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
