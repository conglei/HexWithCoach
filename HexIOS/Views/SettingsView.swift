//
//  SettingsView.swift
//  HexIOS
//
//  Settings tab (locked design §4.5): grouped inset lists. Most rows are
//  placeholders wired to real backing as later issues land (model picker = P1-3
//  stage 3, session length, sync = P4, Full Access status, etc.).
//

import HexCore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var model: DictationModel
    let coach: CoachService
    @Bindable var coachPreferences: CoachPreferences
    /// Re-presents the first-run onboarding flow (owned by ContentView).
    @Binding var showOnboarding: Bool
    @Environment(\.openURL) private var openURL

    @State private var account = CloudAccountStatus()
    @State private var iCloudEnabled = SyncPreferences.iCloudEnabled
    @State private var syncAudio = SyncPreferences.syncAudio
    @State private var syncChangedThisLaunch = false

    @State private var apiKeyDraft = ""
    @State private var incognito = CapturePreferences.incognito

    /// On-device pronunciation model delivery (CI-8). Opt-in, not a gate — fluency
    /// coaching works without it (ADR-0002).
    @State private var pronunciationModel = PronunciationModelInstall()

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

                pronunciationModelSection

                privacySection

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
            .onAppear { incognito = CapturePreferences.incognito }
        }
    }

    // MARK: - Pronunciation model (download-on-demand) — CI-8

    @ViewBuilder
    private var pronunciationModelSection: some View {
        Section {
            switch pronunciationModel.phase {
            case .unknown:
                LabeledContent("Pronunciation coaching") { ProgressView() }

            case .notInstalled:
                Button {
                    pronunciationModel.start()
                } label: {
                    Label("Enable pronunciation coaching (\(pronunciationModel.approximateSizeText))",
                          systemImage: "arrow.down.circle")
                }

            case let .downloading(fraction, received, total):
                VStack(alignment: .leading, spacing: 8) {
                    if let fraction {
                        ProgressView(value: fraction) {
                            Text("Downloading pronunciation model")
                        } currentValueLabel: {
                            Text(downloadByteText(received: received, total: total))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView {
                            Text("Downloading pronunciation model")
                        }
                    }
                    Button("Cancel", role: .cancel) { pronunciationModel.cancel() }
                }

            case .installed:
                LabeledContent("Pronunciation coaching") {
                    Label("Installed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }

            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Download failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("Try again") { pronunciationModel.start() }
                }
            }
        } header: {
            Text("Pronunciation")
        } footer: {
            pronunciationModelFooter
        }
        .onAppear { pronunciationModel.refresh() }
    }

    @ViewBuilder
    private var pronunciationModelFooter: some View {
        switch pronunciationModel.phase {
        case .installed:
            Text("The on-device pronunciation model is installed. Pronunciation feedback is scored locally — nothing leaves your device.")
        case .downloading:
            Text("You can keep using Hex while this downloads. If it's interrupted, it resumes where it left off.")
        default:
            Text("Adds on-device pronunciation feedback (scored locally, no key needed). Fluency coaching already works without it — this is an optional one-time download.")
        }
    }

    /// e.g. "120.4 MB of ~600 MB".
    private func downloadByteText(received: Int64, total: Int64?) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        let got = f.string(fromByteCount: received)
        guard let total else { return got }
        return "\(got) of \(f.string(fromByteCount: total))"
    }

    // MARK: - Privacy / capture controls (RC-8)

    @ViewBuilder
    private var privacySection: some View {
        Section {
            Toggle(isOn: $incognito) {
                Label("Incognito", systemImage: "eyeglasses")
            }
            .onChange(of: incognito) { _, value in CapturePreferences.incognito = value }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Capture stays on this device by default — your dictations (text and audio) are kept locally, and the Coach only uploads when you connect a key. Incognito keeps nothing from new dictations. Password and other secure fields use the system keyboard, so they're never captured.")
        }
    }

    // MARK: - Coach (BYOK, opt-in) — CE-1

    @ViewBuilder
    private var coachSection: some View {
        Section {
            Toggle("Enable Coach", isOn: $coachPreferences.enabled)

            if coachPreferences.enabled {
                if coachPreferences.hasAPIKey {
                    LabeledContent("Gemini API key") {
                        Label("Saved", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    }
                    LabeledContent("This month", value: monthSpendText)
                    Picker("Monthly cap", selection: monthlyCapSelection) {
                        Text("Off").tag(Double?.none)
                        Text("$1").tag(Double?.some(1))
                        Text("$5").tag(Double?.some(5))
                        Text("$10").tag(Double?.some(10))
                        Text("$20").tag(Double?.some(20))
                    }
                    if coach.budgetReached {
                        Text("Monthly cap reached — raise it to keep coaching.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Remove key", role: .destructive) {
                        coachPreferences.clearAPIKey()
                        apiKeyDraft = ""
                    }
                } else {
                    SecureField("Paste your Gemini API key", text: $apiKeyDraft)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Save key") {
                        coachPreferences.saveAPIKey(apiKeyDraft)
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

    private var spendText: String {
        coach.totalCostUSD < 0.01 ? "< $0.01" : String(format: "$%.2f", coach.totalCostUSD)
    }

    private var monthSpendText: String {
        coach.spentThisMonthUSD < 0.01 ? "< $0.01" : String(format: "$%.2f", coach.spentThisMonthUSD)
    }

    /// Binds the cap Picker to the service's budget, persisting through the setter.
    private var monthlyCapSelection: Binding<Double?> {
        Binding(
            get: { coach.budget.monthlyCapUSD },
            set: { coach.budget.monthlyCapUSD = $0 }
        )
    }

    @ViewBuilder
    private var coachFooter: some View {
        if !coachPreferences.enabled {
            Text("The Coach reviews your real speech and suggests more natural phrasing. It’s off by default.")
        } else if !coachPreferences.hasAPIKey {
            Text("Add your own Gemini API key to turn it on. When the Coach is on, your dictations (text and audio) are sent to Google’s Gemini API using your key for analysis. Your key is stored in this device’s Keychain and never synced.")
        } else {
            Text("Coach is on. Your dictations are analyzed with your Gemini key (running cost shown above). Capture stays on this device; remove the key anytime to stop.")
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
