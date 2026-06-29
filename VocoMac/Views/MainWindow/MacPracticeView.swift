//
//  MacPracticeView.swift
//  VocoMac
//
//  Practice section of the macOS Coach hub. PLACEHOLDER (MC-R5) — composed by
//  `MacCoachView` so MC-R6 can fill it in parallel without touching the hub.
//
//  TODO(MC-R6): Replace this placeholder with the macOS Practice surface — a paste
//  hero, coach-generated drills, shadowing, and the promoted phrasebook, mirroring
//  the iOS `PracticeView`. The "Say it better" card action in `MacCoachView` is the
//  deep-link target into this surface (hook left for MC-R6 / MC-R9). `@Query`
//  practice/phrasebook entities off the injected shared `ModelContainer`.
//

import SwiftUI

struct MacPracticeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Practice", systemImage: "mic")
        } description: {
            Text("Drills, shadowing, and your phrasebook will live here. Use “Say it better” on a coaching card to practice it out loud.")
        }
    }
}
