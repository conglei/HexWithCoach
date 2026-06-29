//
//  MacProgressView.swift
//  VocoMac
//
//  Progress section of the macOS Coach hub. PLACEHOLDER (MC-R5) — composed by
//  `MacCoachView` so MC-R7 can fill it in parallel without touching the hub.
//
//  TODO(MC-R7): Replace this placeholder with the macOS Progress digest — the
//  streak, per-lens levels + objective trends, the pronunciation GOP summary, wins
//  (mastered patterns), and the next focus, mirroring the iOS `ProgressDigestView`.
//  Drive it off the pure `ProgressSummary` / `LearnerProfile` (VocoCore) and
//  `@Query` `TranscriptEntry` off the injected shared `ModelContainer`.
//

import SwiftUI

struct MacProgressView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Your streak, per-lens levels, and pronunciation trends will appear here as you keep speaking.")
        }
    }
}
