//
//  SyncPrivacySettingsView.swift
//  VocoMac
//
//  Plain-SwiftUI settings panes introduced with the tabbed Settings redesign
//  (MC-R11):
//
//   • `PronunciationModelSectionView` — a Models-tab row reporting whether the
//     sideloaded GOP pronunciation assets are present (`MacPronunciationAssets.ready`).
//     There is no hosted downloader yet, so when missing we explain the feature and
//     offer to reveal the container's `Application Support/Pronunciation/` folder.
//
//   • `SyncPrivacySettingsView` — the Sync & Privacy pane: an iCloud-sync toggle
//     bound to `SyncPreferences.iCloudEnabled` (the container is built once at
//     launch, so the toggle is annotated "takes effect on next launch") plus a live
//     iCloud account-status line from `CKContainer(identifier: SyncStore.cloudContainerID)`.
//
//  Both are TCA-free; they read/write the App-Group-backed `SyncPreferences` and
//  the `MacPronunciationAssets` helper directly.
//

import CloudKit
import VocoCore
import SwiftUI

// MARK: - Models tab: Pronunciation model row

/// Reports installation status of the sideloaded pronunciation (GOP) assets used
/// for word-level pronunciation coaching. The model archive isn't hosted yet, so
/// we don't offer a download — only a reveal-in-Finder affordance for sideloading.
struct PronunciationModelSectionView: View {
    @State private var isReady = MacPronunciationAssets.ready

    /// The container's sideload folder: `…/Application Support/Pronunciation/`.
    private var sideloadFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pronunciation", isDirectory: true)
    }

    var body: some View {
        Section("Pronunciation Model") {
            HStack {
                Label("Pronunciation coaching", systemImage: "waveform")
                Spacer()
                if isReady {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text("Not installed")
                        .foregroundStyle(.secondary)
                }
            }

            if !isReady {
                Text("Enables word-level pronunciation feedback (phoneme scoring + forced alignment) on top of the always-on fluency coaching. The model is sideloaded today — drop the assets into the folder below and relaunch.")
                    .settingsCaption()

                HStack {
                    Spacer()
                    Button("Reveal Sideload Folder in Finder") {
                        revealSideloadFolder()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .onAppear { isReady = MacPronunciationAssets.ready }
    }

    private func revealSideloadFolder() {
        guard let folder = sideloadFolder else { return }
        // Create it so Finder has something to open and the user can drop assets in.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

// MARK: - Sync & Privacy tab

/// iCloud sync toggle + account-status line. The synced container is constructed
/// once at launch (`SyncStore.makeContainer()` reads `SyncPreferences.iCloudEnabled`
/// then), so flipping the toggle is annotated as taking effect on next launch.
struct SyncPrivacySettingsView: View {
    @State private var iCloudEnabled = SyncPreferences.iCloudEnabled
    @State private var accountStatus: CKAccountStatus?
    @State private var accountStatusError: String?

    var body: some View {
        Form {
            Section("iCloud Sync") {
                Label {
                    Toggle("Sync history via iCloud", isOn: $iCloudEnabled)
                        .onChange(of: iCloudEnabled) { _, newValue in
                            SyncPreferences.iCloudEnabled = newValue
                        }
                } icon: {
                    Image(systemName: "icloud")
                }
                Text("Keeps your notes and coaching in sync across your devices through your private iCloud database. Takes effect on next launch.")
                    .settingsCaption()

                HStack {
                    Label("iCloud account", systemImage: "person.crop.circle")
                    Spacer()
                    Text(accountStatusDescription)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await refreshAccountStatus()
        }
    }

    private var accountStatusDescription: String {
        if let accountStatusError {
            return accountStatusError
        }
        guard let accountStatus else { return "Checking…" }
        switch accountStatus {
        case .available: return "Signed in"
        case .noAccount: return "No iCloud account"
        case .restricted: return "Restricted"
        case .couldNotDetermine: return "Unavailable"
        case .temporarilyUnavailable: return "Temporarily unavailable"
        @unknown default: return "Unknown"
        }
    }

    private func refreshAccountStatus() async {
        let container = CKContainer(identifier: SyncStore.cloudContainerID)
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                accountStatus = status
                accountStatusError = nil
            }
        } catch {
            await MainActor.run {
                accountStatusError = "Unavailable"
            }
        }
    }
}
