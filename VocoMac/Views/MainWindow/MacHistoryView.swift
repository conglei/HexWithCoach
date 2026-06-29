//
//  MacHistoryView.swift
//  VocoMac
//
//  Companion-window "History" section. SHELL placeholder (MC-R0) — empty state only.
//
//  TODO(MC-R8): Replace this placeholder with the History surface — a Notes|Dictation
//  segmented control (HS-1) over a windowed / paginated fetch (HS-2) of the lean
//  `TranscriptEntry` row. `@Query` `TranscriptEntry` off the injected shared
//  `ModelContainer`. See docs/macos-companion-phase3-reconcile.md §5.
//

import SwiftUI

struct MacHistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "History",
            systemImage: "clock",
            description: Text("Your Notes and Dictation history is coming soon.")
        )
    }
}
