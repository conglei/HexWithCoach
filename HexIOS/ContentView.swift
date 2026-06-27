//
//  ContentView.swift
//  HexIOS
//
//  Root tab bar (locked design §2): Home / History / Settings. On iOS 26 this
//  renders as the floating pill tab bar automatically. Owns model lifecycle
//  (prepare) and the global error alert.
//

import SwiftData
import SwiftUI

/// The three root tabs, used as TabView selection tags so deep links can switch.
enum AppTab: Hashable {
    case home, history, settings
}

struct ContentView: View {
    let model: DictationModel
    /// Selected tab, bound from the app so deep links (e.g. the keyboard's
    /// settings button → `hexkb://settings`) can switch tabs.
    @Binding var selectedTab: AppTab

    /// First-run flag (stored in the shared App Group so the keyboard can read it
    /// later if needed). When false, onboarding is presented full-screen.
    @AppStorage(OnboardingState.didOnboardKey, store: OnboardingState.store)
    private var didOnboard = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(model: model)
                .tabItem { Label("Home", systemImage: "mic") }
                .tag(AppTab.home)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(AppTab.history)

            SettingsView(model: model, showOnboarding: $showOnboarding)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(.accentColor)
        .task { await model.prepare() }
        .onAppear { if !didOnboard { showOnboarding = true } }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { didOnboard = true }) {
            OnboardingView(model: model)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            presenting: model.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: TranscriptEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ContentView(model: DictationModel(modelContext: container.mainContext), selectedTab: .constant(.home))
        .modelContainer(container)
}
