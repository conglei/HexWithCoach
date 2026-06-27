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

    /// Still loading the model / setting up — the bounce shouldn't be a blank wait.
    private var isPreparing: Bool { !model.awaitingSwipeBack }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                icon

                if isPreparing {
                    VStack(spacing: 8) {
                        Text("Preparing dictation…").font(.title2.weight(.bold))
                        Text(prepareDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
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
            }

            Spacer()

            VStack(spacing: 12) {
                if isPreparing {
                    Button("Cancel") { model.endSession() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Got it") { model.dismissSwipeBackHint() }
                        .buttonStyle(HexGradientButtonStyle())
                        .padding(.horizontal, 32)
                    Button("Turn off dictation") { model.endSession() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            Circle()
                .fill(HexTheme.gradient)
                .frame(width: 96, height: 96)
                .shadow(color: HexTheme.gradientColors[1].opacity(0.35), radius: 18, y: 10)
            if isPreparing {
                ProgressView().tint(.white).scaleEffect(1.3)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var prepareDetail: String {
        if model.modelState == .loading, model.modelProgress > 0 {
            return "Loading the speech model… \(Int(model.modelProgress * 100))%"
        }
        return "Getting the speech model ready — this takes a few seconds the first time."
    }

    private var sessionHint: String {
        guard let expires = model.sessionExpiresAt else { return "Stays on until you turn it off" }
        let minutes = max(1, Int(expires.timeIntervalSinceNow / 60))
        return "Stays on for ~\(minutes) min"
    }
}
