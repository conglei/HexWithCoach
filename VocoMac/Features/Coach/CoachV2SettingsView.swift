//
//  CoachV2SettingsView.swift
//  VocoMac
//
//  Settings UI for the Coach v2 two-lane engine (MC-R4): opt-in, BYOK Gemini key
//  (stored per-device in the Keychain via `CoachKeychain`, never synced), the
//  automatic-LLM toggle, the monthly budget cap, and the cloud-upload disclosure.
//  Binds directly to the `@Observable` `MacCoachPreferences` / `MacCoachService`
//  (VocoEngine + VocoMac) owned by `MacTranscriptStore` — not through TCA, per the
//  design (the coach driver is a plain observable invoked from the app layer).
//
//  This is the sole Coach settings surface; the legacy TCA-based pronunciation
//  settings view (`CoachSettingsView`) was removed in MC-R4 (carry of MC-6).
//

import VocoCore
import SwiftUI

/// Reads the shared driver off `MacTranscriptStore.shared`. Renders nothing until
/// the store is bootstrapped (so unit tests that never bootstrap are unaffected).
struct CoachV2SettingsView: View {
	var body: some View {
		if let prefs = MacTranscriptStore.shared.coachPreferences,
		   let coach = MacTranscriptStore.shared.coach {
			CoachV2SettingsForm(preferences: prefs, coach: coach)
		}
	}
}

private struct CoachV2SettingsForm: View {
	@Bindable var preferences: MacCoachPreferences
	@Bindable var coach: MacCoachService

	@State private var apiKeyInput = ""

	var body: some View {
		Section {
			Label {
				Toggle("English Coach", isOn: $preferences.enabled)
				Text("Always-on objective feedback (pace, fillers, pauses) is computed on-device for free. Turn this on to also get LLM-written coaching when you add a key.")
					.settingsCaption()
			} icon: {
				Image(systemName: "graduationcap")
			}

			if preferences.enabled {
				apiKeyRow
				autoLLMRow
				budgetRow
				if coach.budgetReached {
					Label {
						Text("This month's budget cap has been reached — LLM coaching is paused until next month or until you raise the cap.")
							.settingsCaption()
					} icon: {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
					}
				}
			}
		} header: {
			Text("English Coach")
		} footer: {
			privacyFooter
		}
	}

	// MARK: - API key

	private var apiKeyRow: some View {
		Label {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Gemini API Key")
					Spacer()
					Text(preferences.hasAPIKey ? "Stored" : "Not set")
						.settingsCaption()
				}

				HStack(spacing: 8) {
					SecureField("Paste your Gemini API key", text: $apiKeyInput)
						.textFieldStyle(.roundedBorder)

					Button("Save") {
						preferences.saveAPIKey(apiKeyInput)
						apiKeyInput = ""
					}
					.disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

					if preferences.hasAPIKey {
						Button("Remove", role: .destructive) {
							preferences.clearAPIKey()
						}
					}
				}

				Text("Bring your own Gemini key. It's stored only on this Mac (Keychain) and is never synced to your other devices.")
					.settingsCaption()
			}
		} icon: {
			Image(systemName: "key.fill")
		}
	}

	// MARK: - Auto LLM

	private var autoLLMRow: some View {
		Label {
			Toggle("Automatically run LLM coaching", isOn: $preferences.autoLLM)
			Text("Coach new dictations in the background, bounded by the budget cap below. Turn off to only run LLM coaching when you ask.")
				.settingsCaption()
		} icon: {
			Image(systemName: "wand.and.stars")
		}
	}

	// MARK: - Budget

	private var budgetRow: some View {
		Label {
			VStack(alignment: .leading, spacing: 6) {
				Toggle("Cap monthly spend", isOn: Binding(
					get: { coach.budget.monthlyCapUSD != nil },
					set: { on in
						coach.budget = CoachBudget(monthlyCapUSD: on ? (coach.budget.monthlyCapUSD ?? 5) : nil)
					}
				))

				if let cap = coach.budget.monthlyCapUSD {
					HStack {
						Text("Monthly cap")
						Spacer()
						Text(String(format: "$%.2f", cap))
							.foregroundStyle(.secondary)
							.font(.system(.body, design: .monospaced))
					}
					Slider(
						value: Binding(
							get: { cap },
							set: { coach.budget = CoachBudget(monthlyCapUSD: $0) }
						),
						in: 1...50,
						step: 1
					)
				}

				HStack {
					Text("Spent this month")
					Spacer()
					Text(String(format: "$%.2f", coach.spentThisMonthUSD))
						.settingsCaption()
				}
			}
		} icon: {
			Image(systemName: "dollarsign.circle")
		}
	}

	// MARK: - Privacy

	private var privacyFooter: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Privacy")
				.font(.footnote.weight(.semibold))
			Text("Objective coaching runs entirely on-device. When LLM coaching is enabled with a key, your dictation transcripts (and, when available, the recorded audio) are uploaded to Google's Gemini API for analysis. Nothing else is sent. Your key is stored in this Mac's Keychain and never synced. You can turn the coach off at any time.")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
		.padding(.top, 4)
	}
}
