//
//  HexWidgetsLiveActivity.swift
//  HexWidgets
//
//  Flow Session Live Activity: a calm "you can dictate" indicator on the Lock
//  Screen + Dynamic Island while a session is active, with an End button. Uses the
//  shared FlowSessionAttributes from HexCore.
//
//  Design: the Lock Screen stays one steady state — a mic and "Ready to dictate" —
//  because you're rarely staring at the Lock Screen mid-utterance. The live
//  "speaking now" feedback (mic → waveform) lives only in the Dynamic Island,
//  where you actually see it while dictating in another app.
//

import ActivityKit
import AppIntents
import HexCore
import SwiftUI
import WidgetKit

struct HexWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlowSessionAttributes.self) { context in
            // Lock Screen / banner — one steady, quiet state.
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("Ready to dictate")
                    .font(.headline)
                Spacer()
                endButton.buttonStyle(.bordered)
            }
            .padding()
            .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { islandGlyph(context).font(.title3) }
                DynamicIslandExpandedRegion(.trailing) { countdown(context).font(.body).foregroundStyle(.secondary) }
                DynamicIslandExpandedRegion(.center) {
                    Text("Ready to dictate").font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    endButton.buttonStyle(.bordered)
                }
            } compactLeading: {
                islandGlyph(context)
            } compactTrailing: {
                countdown(context).monospacedDigit().foregroundStyle(.secondary)
            } minimal: {
                islandGlyph(context)
            }
            .keylineTint(.accentColor)
        }
    }

    private var endButton: some View {
        Button(intent: EndFlowSessionIntent()) {
            Label("End", systemImage: "stop.fill")
        }
        .tint(.accentColor)
    }

    /// Mic when waiting, waveform while you're actually speaking — Dynamic Island only.
    private func islandGlyph(_ context: ActivityViewContext<FlowSessionAttributes>) -> some View {
        Image(systemName: context.state.isCapturing ? "waveform" : "mic.fill")
            .foregroundStyle(.tint)
    }

    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<FlowSessionAttributes>) -> some View {
        if let endsAt = context.state.endsAt, endsAt > Date() {
            Text(timerInterval: Date() ... endsAt, countsDown: true)
        } else {
            EmptyView()
        }
    }
}

#Preview("Flow Session", as: .content, using: FlowSessionAttributes()) {
    HexWidgetsLiveActivity()
} contentStates: {
    FlowSessionAttributes.ContentState(endsAt: Date().addingTimeInterval(600), isCapturing: false)
    FlowSessionAttributes.ContentState(endsAt: Date().addingTimeInterval(600), isCapturing: true)
}
