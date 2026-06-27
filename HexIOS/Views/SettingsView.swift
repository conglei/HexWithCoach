//
//  SettingsView.swift
//  HexIOS
//
//  Settings tab (locked design §4.5): grouped inset lists. Most rows are
//  placeholders wired to real backing as later issues land (model picker = P1-3
//  stage 3, session length, sync = P4, Full Access status, etc.).
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var model: DictationModel
    /// Re-presents the first-run onboarding flow (owned by ContentView).
    @Binding var showOnboarding: Bool
    @Environment(\.openURL) private var openURL

    @State private var account = CloudAccountStatus()
    @State private var iCloudEnabled = SyncPreferences.iCloudEnabled
    @State private var syncAudio = SyncPreferences.syncAudio
    @State private var syncChangedThisLaunch = false

    @State private var coach = CoachPreferences()
    @State private var apiKeyDraft = ""

    // Placeholder (formatter seam #199).
    @State private var cleanUpFiller = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Transcription") {
                    LabeledContent("Model", value: model.modelName)
                    Picker("Session length", selection: $model.sessionLength) {
                        ForEach(SessionLength.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Language", value: "Automatic")
                    NavigationLink("Vocabulary") { vocabularyPlaceholder }
                }

                Section {
                    Toggle("iCloud sync", isOn: $iCloudEnabled)
                        .onChange(of: iCloudEnabled) { _, value in
                            SyncPreferences.iCloudEnabled = value
                            syncChangedThisLaunch = true
                        }
                    accountStatusRow
                    Toggle("Sync audio (Wi-Fi only)", isOn: $syncAudio)
                        .onChange(of: syncAudio) { _, value in SyncPreferences.syncAudio = value }
                        .disabled(!iCloudEnabled)
                } header: {
                    Text("iCloud")
                } footer: {
                    syncFooter
                }
                .task { await account.refresh() }

                coachSection

                Section {
                    Toggle("Clean up filler words", isOn: $cleanUpFiller).disabled(true)
                } footer: {
                    Text("Removes “um”, “uh”, and tidies punctuation. Coming soon.")
                }

                Section("Keyboard") {
                    LabeledContent("Full Access") {
                        Text("Check in Settings")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Set up Hex", systemImage: "checklist")
                    }
                } footer: {
                    Text("Re-run the setup checklist for the keyboard, permissions, and model.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Coach (BYOK, opt-in) — CE-1

    @ViewBuilder
    private var coachSection: some View {
        Section {
            Toggle("Enable Coach", isOn: $coach.enabled)

            if coach.enabled {
                if coach.hasAPIKey {
                    LabeledContent("Gemini API key") {
                        Label("Saved", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    }
                    Button("Remove key", role: .destructive) {
                        coach.clearAPIKey()
                        apiKeyDraft = ""
                    }
                } else {
                    SecureField("Paste your Gemini API key", text: $apiKeyDraft)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Save key") {
                        coach.saveAPIKey(apiKeyDraft)
                        apiKeyDraft = ""
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Link("Get a Gemini API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                }
            }
        } header: {
            Text("Coach")
        } footer: {
            coachFooter
        }
    }

    @ViewBuilder
    private var coachFooter: some View {
        if !coach.enabled {
            Text("The Coach reviews your real speech and suggests more natural phrasing. It’s off by default.")
        } else if !coach.hasAPIKey {
            Text("Add your own Gemini API key to turn it on. When the Coach is on, your dictations (text and audio) are sent to Google’s Gemini API using your key for analysis. Your key is stored in this device’s Keychain and never synced.")
        } else {
            Text("Coach is on. Your dictations (text and audio) are sent to Google’s Gemini API using your key for analysis. Capture stays on this device until then; remove the key anytime to stop.")
        }
    }

    @ViewBuilder
    private var accountStatusRow: some View {
        switch account.state {
        case .unknown:
            LabeledContent("Account") { ProgressView() }
        case .available:
            LabeledContent("Account") {
                Label("Signed in", systemImage: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
        case .noAccount:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Not signed in — open Settings", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            }
        case .restricted:
            LabeledContent("Account", value: "Restricted")
        case .unavailable:
            LabeledContent("Account", value: "Unavailable")
        }
    }

    @ViewBuilder
    private var syncFooter: some View {
        if syncChangedThisLaunch {
            Text("Restart Hex to apply the sync change.")
        } else if !iCloudEnabled {
            Text("History is kept on this device only.")
        } else {
            switch account.state {
            case .noAccount:
                Text("Sign in to iCloud (Settings ▸ your name) to sync history across your devices.")
            case .restricted, .unavailable:
                Text("iCloud is unavailable, so history stays on this device for now.")
            default:
                Text("History syncs across your devices via iCloud. Audio isn’t stored yet, so audio sync has no effect.")
            }
        }
    }

    private var vocabularyPlaceholder: some View {
        ContentUnavailableView(
            "Vocabulary",
            systemImage: "character.book.closed",
            description: Text("Custom words and replacements will live here.")
        )
    }
}
