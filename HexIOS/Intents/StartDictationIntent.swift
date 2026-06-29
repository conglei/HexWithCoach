//
//  StartDictationIntent.swift
//  HexIOS
//
//  Hands-free entry (P3-2): start a Flow Session from Shortcuts / the Action
//  Button / Siri. Like the keyboard bounce, starting the mic session requires
//  the app to be foreground, so the intent opens the app (`openAppWhenRun`) and
//  records a pending request; the app starts the session when it becomes active
//  (see HexIOSApp), which avoids a cold-launch race.
//

import AppIntents
import Foundation
import HexCore

// `PendingAppAction` (the App Group handoff that lets a session-start request
// survive until the app is foreground) now lives in HexCore so the widget
// extension's Control Center / Lock Screen control can use it too.

struct StartDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Dictation"
    static var description = IntentDescription("Start a hands-free Hex dictation session.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingAppAction.requestStartSession()
        return .result()
    }
}

struct HexAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Start dictation with \(.applicationName)",
                "Dictate with \(.applicationName)",
            ],
            shortTitle: "Start Dictation",
            systemImageName: "mic.fill"
        )
    }
}
