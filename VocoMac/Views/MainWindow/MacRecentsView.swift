//
//  MacRecentsView.swift
//  VocoMac
//
//  Companion-window recents / quick-note pane. SHELL placeholder (MC-R0) — empty
//  state only. Lives in the sidebar footer rather than as its own section: capture
//  stays the always-on menu-bar hotkey, and this is the glanceable recents surface
//  that leans into "macOS = all-day capture hub" (decision 2026-06-29).
//
//  TODO(MC-R5/MC-R8): Replace this placeholder with a live recents list — the most
//  recent `TranscriptEntry` rows (`@Query` off the injected shared `ModelContainer`,
//  newest first) plus a lightweight quick-note affordance. See
//  docs/macos-companion-phase3-reconcile.md §5.
//

import SwiftUI

struct MacRecentsView: View {
    var body: some View {
        ContentUnavailableView(
            "Recents",
            systemImage: "tray.full",
            description: Text("Your latest captures will appear here.")
        )
        .symbolVariant(.none)
        .controlSize(.small)
    }
}
