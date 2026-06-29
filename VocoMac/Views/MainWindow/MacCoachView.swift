//
//  MacCoachView.swift
//  VocoMac
//
//  Companion-window "Coach" section. SHELL placeholder (MC-R0) — empty state only.
//
//  TODO(MC-R5): Replace this placeholder with the real Coach hub — the Review feed
//  (card / `CoachObservation` projections), Practice (drills + paste + phrasebook),
//  and the Progress digest. `@Query` `CoachObservation` / `CoachCardEntity` off the
//  injected shared `ModelContainer`. See docs/macos-companion-phase3-reconcile.md §5.
//

import SwiftUI

struct MacCoachView: View {
    var body: some View {
        ContentUnavailableView(
            "Coach",
            systemImage: "graduationcap",
            description: Text("Your coaching feed, practice drills, and progress digest are coming soon.")
        )
    }
}
