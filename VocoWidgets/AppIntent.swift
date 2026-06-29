//
//  AppIntent.swift
//  HexWidgets
//
//  Intent backing the Control Center / Lock Screen "Start dictation" control. It
//  can't reach the app's model directly, so it records a pending request in the
//  App Group and opens the app, which starts the Flow Session on activation —
//  the same handoff the Shortcuts / Action Button entry uses.
//

import AppIntents
import VocoCore

struct StartDictationControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Start dictation"
    static var description = IntentDescription("Start a Voco dictation session.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingAppAction.requestStartSession()
        return .result()
    }
}
