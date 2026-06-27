//
//  SwipeBackView.swift
//  HexIOS
//
//  Shown the moment a Flow Session starts — most importantly after the keyboard
//  bounces into the app via `hexkb://startSession`. It overlays whatever tab was
//  showing (previously the bounce could just dump you on Settings), with one clear
//  instruction: swipe back to your app and tap the Hex mic.
//

import SwiftUI

struct SwipeBackView: View {
    let model: DictationModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(HexTheme.gradient, in: .circle)
                    .shadow(color: HexTheme.gradientColors[1].opacity(0.35), radius: 18, y: 10)

                VStack(spacing: 8) {
                    Text("Dictation is on").font(.title.weight(.bold))
                    Text("Swipe back to your app, then tap the Hex mic to start talking.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Label(sessionHint, systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: .capsule)
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Got it") { model.dismissSwipeBackHint() }
                    .buttonStyle(HexGradientButtonStyle())
                    .padding(.horizontal, 32)
                Button("Turn off dictation") { model.endSession() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var sessionHint: String {
        guard let expires = model.sessionExpiresAt else { return "Stays on until you turn it off" }
        let minutes = max(1, Int(expires.timeIntervalSinceNow / 60))
        return "Stays on for ~\(minutes) min"
    }
}
