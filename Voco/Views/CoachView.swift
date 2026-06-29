//
//  CoachView.swift
//  HexIOS
//
//  The Coach tab (IA-1) — the single learning hub that merges the Review feed
//  (feedback cards curated from your real speech) and Practice (drills) so the
//  app keeps four tabs (Home / History / Coach / Settings) without burying
//  practice behind a fifth.
//
//  Feedback is the primary surface and reuses `ReviewView`'s feed verbatim —
//  same cards, streak header, key/upsell banner, and navigation to detail. This
//  view owns the `NavigationStack`, the title, and a "Feedback | Practice"
//  segmented control so both surfaces share one nav bar. Phrasebook and the
//  Progress digest stay reachable exactly as Review exposed them (bookmark
//  toolbar item + the streak header link inside the feed).
//
//  Practice (PR-2) is the drill surface: a paste hero, coach-generated drills,
//  and the promoted phrasebook — see `PracticeView`.
//

import SwiftUI

struct CoachView: View {
    let coach: CoachService
    let preferences: CoachPreferences
    @Binding var selectedTab: AppTab

    /// Which half of the Coach hub is showing. Feedback is the default so the
    /// Coach tab opens onto the existing Review feed with no behavior change.
    private enum Surface: String, CaseIterable, Identifiable {
        case feedback = "Feedback"
        case practice = "Practice"
        var id: Self { self }
    }

    @State private var surface: Surface = {
        #if DEBUG
        // DEBUG-only: a seeded screenshot / QA run can open straight onto Practice
        // with the `-VOCOCoachPractice` launch argument, so the word-swap drill is
        // reachable without driving the segmented control. No effect in release.
        if ProcessInfo.processInfo.arguments.contains("-VOCOCoachPractice") { return .practice }
        #endif
        return .feedback
    }()

    var body: some View {
        NavigationStack {
            Group {
                switch surface {
                case .feedback:
                    // Reuse the Review feed verbatim (cards, streak header,
                    // upsell, detail navigation, and the manual-review toolbar).
                    // `embedded: true` drops Review's own NavigationStack/title
                    // so it lives under our nav bar — but it's a *real installed
                    // view*, so its `@Query`/`@State` bind to the environment's
                    // modelContext and the feed actually shows its cards (FX-1).
                    ReviewView(coach: coach, preferences: preferences, selectedTab: $selectedTab, embedded: true)
                case .practice:
                    PracticeView()
                }
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Coach surface", selection: $surface) {
                        ForEach(Surface.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
                // Phrasebook stays one tap away, exactly as Review exposed it.
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { PhrasebookView() } label: { Image(systemName: "bookmark") }
                }
            }
        }
    }
}
