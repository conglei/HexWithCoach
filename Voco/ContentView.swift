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

/// The root tabs, used as TabView selection tags so deep links can switch.
enum AppTab: Hashable {
    case review, home, history, settings
}

struct ContentView: View {
    let model: DictationModel
    let coach: CoachService
    let coachPreferences: CoachPreferences
    /// Selected tab, bound from the app so deep links (e.g. the keyboard's
    /// settings button → `voco://settings`) can switch tabs.
    @Binding var selectedTab: AppTab

    /// First-run flag (stored in the shared App Group so the keyboard can read it
    /// later if needed). When false, onboarding is presented full-screen.
    @AppStorage(OnboardingState.didOnboardKey, store: OnboardingState.store)
    private var didOnboard = false
    @State private var showOnboarding = false
    /// History's navigation stack, owned here so "See all" can reset it to root.
    @State private var historyPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            ReviewView(coach: coach, preferences: coachPreferences, selectedTab: $selectedTab)
                .tabItem { Label("Review", systemImage: "sparkles") }
                .tag(AppTab.review)

            HomeView(model: model, selectedTab: $selectedTab, onShowAllHistory: {
                historyPath = NavigationPath()
                selectedTab = .history
            })
                .tabItem { Label("Home", systemImage: "mic") }
                .tag(AppTab.home)

            HistoryView(path: $historyPath)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(AppTab.history)

            SettingsView(model: model, coach: coach, coachPreferences: coachPreferences, showOnboarding: $showOnboarding)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(.accentColor)
        // Make the coach reachable from pushed views (transcript detail, History
        // rows) for the manual LLM override action.
        .environment(coach)
        .task {
            // Automatic two-lane analysis (CI-7): every saved transcript runs the
            // always-on objective lane (and the gated LLM lane) in the background —
            // no manual button. Wire the capture hook before recovery so recovered
            // notes are coached too.
            model.onTranscriptSaved = { [coach] entry in
                await coach.autoAnalyzeOnCapture(entry)
            }
            await model.prepare()
            // Auto-recover a note interrupted by a crash/kill (e.g. paused, then the
            // app was terminated) — transcribes the saved spans and files it silently.
            await model.recoverInterruptedNote()
            // Backfill the free objective lane over notes captured before always-on
            // analysis existed, then auto-batch the LLM lane if it's enabled + funded.
            await coach.backfillObjectiveBacklog()
            await coach.maybeAutoRunLLMBacklog()
        }
        .onAppear { if !didOnboard { showOnboarding = true } }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { didOnboard = true }) {
            OnboardingView(model: model)
        }
        // A Flow Session just started (e.g. the keyboard bounced via voco://
        // startSession): show a dedicated swipe-back screen over any tab.
        .fullScreenCover(isPresented: Binding(
            get: { model.awaitingSwipeBack || model.isStartingSession },
            set: { if !$0 { model.dismissSwipeBackHint() } }
        )) {
            SwipeBackView(model: model)
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
        for: TranscriptEntry.self, TranscriptAnalysis.self, CoachCardEntity.self,
        CoachObservation.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let prefs = CoachPreferences()
    return ContentView(
        model: DictationModel(modelContext: container.mainContext),
        coach: CoachService(modelContext: container.mainContext, preferences: prefs),
        coachPreferences: prefs,
        selectedTab: .constant(.review)
    )
    .modelContainer(container)
    .environment(CoachService(modelContext: container.mainContext, preferences: prefs))
}
