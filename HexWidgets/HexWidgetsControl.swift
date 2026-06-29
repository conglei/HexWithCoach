//
//  HexWidgetsControl.swift
//  HexWidgets
//
//  Control Center / Lock Screen control: one tap to start a Voco dictation
//  session, so you can dictate into another app without digging through the
//  keyboard switcher.
//

import AppIntents
import SwiftUI
import WidgetKit

struct HexWidgetsControl: ControlWidget {
    static let kind: String = "stonefrontier.HexIOS.StartDictation"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartDictationControlIntent()) {
                Label("Dictate", systemImage: "mic.fill")
            }
        }
        .displayName("Start dictation")
        .description("Start a Voco dictation session.")
    }
}
