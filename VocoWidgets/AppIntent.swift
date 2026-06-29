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

/// Home Screen widget mic button: open the app and start recording a new note.
/// Like the control intent, it can't reach the app's model, so it records a
/// pending request and lets the app start the note on activation.
struct RecordNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Record a note"
    static var description = IntentDescription("Start recording a new note in Voco.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingAppAction.requestRecordNote()
        return .result()
    }
}

/// Home Screen widget status pill: open iOS keyboard settings so the user can
/// turn the Voco keyboard on or off (iOS has no API to toggle it directly).
struct ManageKeyboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Manage Voco keyboard"
    static var description = IntentDescription("Open settings to turn the Voco keyboard on or off.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingAppAction.requestOpenKeyboardSettings()
        return .result()
    }
}
