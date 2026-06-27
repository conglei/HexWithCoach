//
//  HexIOSApp.swift
//  HexIOS
//
//  Created by Conglei Shi on 6/26/26.
//

import SwiftData
import SwiftUI

@main
struct HexIOSApp: App {
    private let modelContainer: ModelContainer
    @State private var model: DictationModel
    @State private var selectedTab: AppTab = .home
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        let container = TranscriptStore.makeContainer()
        modelContainer = container
        _model = State(initialValue: DictationModel(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, selectedTab: $selectedTab)
                .modelContainer(modelContainer)
                .onOpenURL { url in
                    guard url.scheme == "hexkb" else { return }
                    switch url.host {
                    case "startSession":
                        // Keyboard session bounce.
                        Task { await model.startKeyboardSession() }
                    case "settings":
                        // Keyboard toolbar settings icon → Settings tab.
                        selectedTab = .settings
                    default:
                        break
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Hands-free entry (App Intent / Action Button / Siri): the
                    // intent opens the app and flags a request; honor it on activation.
                    guard phase == .active, PendingAppAction.consumeStartSession() else { return }
                    Task { await model.startKeyboardSession() }
                }
        }
    }
}
