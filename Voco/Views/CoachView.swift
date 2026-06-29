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

    @State private var surface: Surface = .feedback

    var body: some View {
        NavigationStack {
            Group {
                switch surface {
                case .feedback:
                    // Reuse the Review feed verbatim (cards, streak header,
                    // upsell, detail navigation). `ReviewView` exposes its inner
                    // content via `feedContent` so we can host it under our own
                    // NavigationStack/title without a nested stack or doubled
                    // title.
                    review.feedContent
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
                // Manual "Review now" override, shared with standalone ReviewView.
                if surface == .feedback {
                    review.feedToolbar
                }
            }
        }
    }

    /// A single `ReviewView` instance reused for both its embeddable `feedContent`
    /// and its `feedToolbar`, so the feed's `@Query`/`@State` are shared.
    private var review: ReviewView {
        ReviewView(coach: coach, preferences: preferences, selectedTab: $selectedTab)
    }
}
