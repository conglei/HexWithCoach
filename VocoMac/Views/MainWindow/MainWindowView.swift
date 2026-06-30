//
//  MainWindowView.swift
//  VocoMac
//
//  The macOS companion window shell, re-cut to the Phase-3 reconciled IA (MC-R0,
//  carried forward from MC-7). A real, native main window hosting the learning
//  experience alongside the menu bar. Standalone SwiftUI + `@Observable` navigation
//  over a `NavigationSplitView` — NOT TCA, per `docs/macos-companion-phase3-reconcile.md` §5.
//
//  This task is the SHELL ONLY: sidebar navigation, window plumbing, the shared
//  `ModelContainer` injected into the environment, and empty-state placeholders.
//  The actual section content is filled in by later tasks:
//
//    • MC-R5 → `MacCoachView`   (Coach hub: Review feed + Practice + Progress)
//    • MC-R8 → `MacHistoryView` (Notes|Dictation segment + windowed fetch)
//    •          `MacRecentsView` (recents / quick-note pane)
//
//  The reconciled IA replaces MC-7's Review/Notebook/History/Progress set with
//  Coach · History + a recents pane (capture stays the menu-bar hotkey). Settings
//  moved out to its own HIG-standard tabbed window (MC-R11).
//
//  The shared `ModelContainer` reaches the environment in `HexAppDelegate`
//  (`presentMainWindow()`), which applies `.modelContainer(MacTranscriptStore.shared.modelContainer!)`
//  to this view so the fan-out screens can `@Query` `TranscriptEntry` / `CoachObservation`.
//

import SwiftUI

/// Sidebar sections of the companion window, mirroring the reconciled Phase-3 IA
/// (`docs/macos-companion-phase3-reconcile.md` §5): Coach · History. Settings is no
/// longer a section here — it moved to a dedicated, HIG-standard tabbed Settings
/// window opened via the status menu / ⌘, (MC-R11). The sections below remain
/// fan-out screens; capture stays the menu-bar hotkey.
enum MainWindowSection: String, CaseIterable, Identifiable, Hashable {
    case coach
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: return "Coach"
        case .history: return "History"
        }
    }

    var systemImage: String {
        switch self {
        case .coach: return "graduationcap"
        case .history: return "clock"
        }
    }
}

/// Root view for the companion window. Owns sidebar selection; routes the detail
/// column to each section view, and carries the recents / quick-note pane as a
/// small footer under the sidebar list (capture itself stays the menu-bar hotkey,
/// per the 2026-06-29 decision).
struct MainWindowView: View {
    @State private var selection: MainWindowSection? = .coach
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(MainWindowSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }

                Divider()

                // Recents footer — a compact, live "latest captures" surface that
                // opens the matching transcript in History. Replaces the old empty
                // placeholder that left the rail reading unfinished (MC-R13). Capture
                // stays the always-on menu-bar hotkey.
                MacRecentsView { entry in
                    selection = .history
                }
            }
            // Tighter rail (MC-R13): the two nav items + a compact recents footer no
            // longer need a wide column with a big empty gap.
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .navigationTitle("Voco")
        } detail: {
            detail(for: selection ?? .coach)
        }
    }

    @ViewBuilder
    private func detail(for section: MainWindowSection) -> some View {
        switch section {
        case .coach:
            MacCoachView()
                .navigationTitle(section.title)
        case .history:
            MacHistoryView()
                .navigationTitle(section.title)
        }
    }
}
