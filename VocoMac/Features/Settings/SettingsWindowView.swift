//
//  SettingsWindowView.swift
//  VocoMac
//
//  HIG-standard macOS Settings surface (MC-R11). Replaces the old nested
//  sub-sidebar `AppView` (Settings/Transforms/History/About) with a native
//  preferences-style `TabView` of icon tabs, hosted in the dedicated Settings
//  window opened via the status menu / ⌘,. The companion main window now shows
//  only Coach · History (+ recents); Settings no longer lives inside it.
//
//  Each tab is a focused pane that reuses the existing store-scoped section views
//  (PermissionsSectionView, ModelSectionView, …) exactly as the old `AppView`
//  detail column did — grouped here into General / Recording / Models / Coach /
//  Sync & Privacy / Transforms / About. The section views emit bare `Section`s,
//  so each pane wraps them in a `Form { … }.formStyle(.grouped)`.
//
//  The Sync & Privacy pane is plain SwiftUI over `SyncPreferences` / `CKContainer`
//  (no TCA), per the design — the sync toggle picks the container config once at
//  launch, so the UI notes it takes effect on next launch.
//

import CloudKit
import ComposableArchitecture
import VocoCore
import SwiftUI

/// Tabs of the macOS Settings window, in display order. `.tabViewStyle(.tabBarOnly)`
/// (the default on macOS for a top-level `TabView` with `Tab`s + `Image`/`Text`
/// labels) renders these as the standard preferences toolbar of icon tabs.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case recording
    case models
    case coach
    case syncPrivacy
    case transforms
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .recording: return "Recording"
        case .models: return "Models"
        case .coach: return "Coach"
        case .syncPrivacy: return "Sync & Privacy"
        case .transforms: return "Transforms"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .recording: return "mic"
        case .models: return "cpu"
        case .coach: return "graduationcap"
        case .syncPrivacy: return "icloud"
        case .transforms: return "text.badge.plus"
        case .about: return "info.circle"
        }
    }
}

/// Root of the dedicated Settings window. A native preferences-style `TabView`
/// whose tabs reuse the existing TCA-scoped section views. Permission status is
/// read off the root `AppFeature` store (the same source the old `AppView` used).
struct SettingsWindowView: View {
    @Bindable var store: StoreOf<AppFeature>
    @State private var selection: SettingsTab = .general

    private var settingsStore: StoreOf<SettingsFeature> {
        store.scope(state: \.settings, action: \.settings)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(SettingsTab.allCases) { tab in
                pane(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        // Drive the shared `SettingsFeature.task` once (microphone enumeration,
        // model status, etc.) — the old flat `SettingsView` did this in `.task`.
        .task {
            await settingsStore.send(.task).finish()
        }
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            Form {
                GeneralSectionView(store: settingsStore)
            }
            .formStyle(.grouped)

        case .recording:
            Form {
                HotKeySectionView(store: settingsStore)
                if store.microphonePermission == .granted {
                    MicrophoneSelectionSectionView(store: settingsStore)
                }
                SoundSectionView(store: settingsStore)
                PermissionsSectionView(
                    store: settingsStore,
                    microphonePermission: store.microphonePermission,
                    accessibilityPermission: store.accessibilityPermission,
                    inputMonitoringPermission: store.inputMonitoringPermission
                )
            }
            .formStyle(.grouped)

        case .models:
            Form {
                ModelSectionView(store: settingsStore, shouldFlash: settingsStore.shouldFlashModelSection)
                // Language picker only applies to WhisperKit models (not Parakeet).
                if ParakeetModel(rawValue: settingsStore.hexSettings.selectedModel) == nil {
                    Section("Language") {
                        LanguageSectionView(store: settingsStore)
                    }
                }
                PronunciationModelSectionView()
            }
            .formStyle(.grouped)

        case .coach:
            Form {
                CoachV2SettingsView()
            }
            .formStyle(.grouped)

        case .syncPrivacy:
            SyncPrivacySettingsView()

        case .transforms:
            WordRemappingsView(store: settingsStore)

        case .about:
            AboutView(store: settingsStore)
        }
    }
}
