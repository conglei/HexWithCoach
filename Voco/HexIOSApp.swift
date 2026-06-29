//
//  HexIOSApp.swift
//  HexIOS
//
//  Created by Conglei Shi on 6/26/26.
//

import VocoCore
import SwiftData
import SwiftUI
import UIKit

@main
struct HexIOSApp: App {
    private let modelContainer: ModelContainer
    @State private var model: DictationModel
    @State private var coachPreferences: CoachPreferences
    @State private var coach: CoachService
    @State private var selectedTab: AppTab = .review
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        let container = TranscriptStore.makeContainer()
        modelContainer = container
        TranscriptStore.ensureUniqueIDs(in: container.mainContext)
        _model = State(initialValue: DictationModel(modelContext: container.mainContext))
        let prefs = CoachPreferences()
        _coachPreferences = State(initialValue: prefs)
        _coach = State(initialValue: CoachService(modelContext: container.mainContext, preferences: prefs))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, coach: coach, coachPreferences: coachPreferences, selectedTab: $selectedTab)
                .modelContainer(modelContainer)
                .onOpenURL { url in
                    guard url.scheme == "voco" else { return }
                    switch url.host {
                    case "startSession":
                        // Keyboard session bounce.
                        Task { await model.startKeyboardSession() }
                    case "record":
                        // Start a new in-app note (Home widget mic button / Shortcuts).
                        startNote()
                    case "settings":
                        // Keyboard toolbar settings icon → Settings tab.
                        selectedTab = .settings
                    case "enableKeyboard":
                        // Home widget tapped while the keyboard isn't set up yet:
                        // iOS won't let us enable it programmatically, so jump
                        // straight to this app's page in Settings (Keyboards lives
                        // there) instead of making the user hunt for it.
                        openKeyboardSettings()
                    default:
                        break
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Hands-free entry: an intent (Action Button / Siri / Control /
                    // Home widget) opens the app and flags a request; honor whichever
                    // is pending on activation. This avoids a cold-launch race.
                    guard phase == .active else { return }
                    if PendingAppAction.consumeStartSession() {
                        Task { await model.startKeyboardSession() }
                    }
                    if PendingAppAction.consumeRecordNote() {
                        startNote()
                    }
                    if PendingAppAction.consumeOpenKeyboardSettings() {
                        openKeyboardSettings()
                    }
                }
        }
    }

    /// Switch to Home and start recording a new note. `prepare()` is idempotent, so
    /// awaiting it here covers the cold-launch case where the model isn't ready yet
    /// when the widget bounces us in.
    private func startNote() {
        selectedTab = .home
        Task {
            await model.prepare()
            guard model.canRecord else { return }
            await model.toggleRecording()
        }
    }

    /// Jump to this app's page in iOS Settings, where the keyboard is turned on/off.
    private func openKeyboardSettings() {
        if let settings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settings)
        }
    }
}
