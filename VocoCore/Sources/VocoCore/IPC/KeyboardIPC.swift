//
//  KeyboardIPC.swift
//  HexCore
//
//  Domain types + channel names for keyboard <-> host-app communication.
//
//  Flow (see docs/ios-keyboard-v1-plan.md):
//    keyboard mic tap --(.captureStart/.captureStop Darwin signal)--> host app
//    host app records + transcribes, writes a DictationResult to the mailbox
//    --(.resultReady Darwin signal)--> keyboard reads mailbox, inserts text.
//

import Foundation

/// The App Group shared by the iOS host app and the keyboard extension. Must
/// match the `group.*` identifier configured (identically) on both targets in
/// Xcode (Signing & Capabilities ▸ App Groups).
public enum HexAppGroup {
    public static let identifier = "group.co.stonefrontier.voco"
}

/// A transcription result handed from the host app to the keyboard.
public struct DictationResult: Codable, Equatable, Sendable, Identifiable {
    /// Stable id so the keyboard can ignore a result it has already inserted.
    public let id: UUID
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Shared "Flow Session" state, written by the host app and read by the keyboard
/// so the keyboard knows whether a re-bounce is needed.
public struct DictationSessionState: Codable, Equatable, Sendable {
    public var isActive: Bool
    /// When the continuous-mic session expires (nil when inactive).
    public var expiresAt: Date?
    /// Last time the host app confirmed the session is genuinely alive. The host
    /// refreshes this on a short interval while the engine runs; if the app dies
    /// or is suspended without ending the session cleanly, it goes stale and the
    /// keyboard stops trusting the (otherwise unexpired) state.
    public var heartbeat: Date

    /// A session whose heartbeat is older than this is considered dead, even if
    /// `expiresAt` is still in the future.
    public static let livenessWindow: TimeInterval = 6

    public init(isActive: Bool, expiresAt: Date?, heartbeat: Date = Date()) {
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.heartbeat = heartbeat
    }

    public static let inactive = DictationSessionState(isActive: false, expiresAt: nil, heartbeat: .distantPast)

    /// Whether the session is currently usable at `now`: active, not expired, and
    /// with a fresh heartbeat (proving the host app is actually running).
    public func isUsable(at now: Date) -> Bool {
        guard isActive else { return false }
        if let expiresAt, now >= expiresAt { return false }
        return now.timeIntervalSince(heartbeat) < Self.livenessWindow
    }
}

/// Cross-process Darwin notification names. Darwin notifications carry no
/// payload, so they only signal "look at the mailbox now".
public enum IPCSignal: String, Sendable, CaseIterable {
    /// keyboard -> host: begin capturing a dictation snippet.
    case captureStart = "co.stonefrontier.hex.ipc.captureStart"
    /// keyboard -> host: stop capturing and transcribe.
    case captureStop = "co.stonefrontier.hex.ipc.captureStop"
    /// host -> keyboard: a new DictationResult is in the mailbox.
    case resultReady = "co.stonefrontier.hex.ipc.resultReady"
    /// host -> keyboard: session state changed (started / ended / expired).
    case sessionChanged = "co.stonefrontier.hex.ipc.sessionChanged"
    /// Live Activity / any surface -> host: end the current session.
    case endSession = "co.stonefrontier.hex.ipc.endSession"
    /// keyboard -> host: the keyboard became active (only fires with Full Access,
    /// since App Group / Darwin access requires it) — used for setup confirmation.
    case keyboardActive = "co.stonefrontier.hex.ipc.keyboardActive"
}

/// Records that the keyboard extension has run with Full Access. The keyboard can
/// only write the App Group when Full Access is granted, so a present timestamp
/// proves the keyboard is both enabled AND has Full Access — which the host app
/// otherwise has no way to detect. Used by onboarding to confirm setup.
public enum KeyboardPresence {
    private static let key = "hex.keyboardLastActiveAt"

    public static func markActive(appGroupIdentifier: String) {
        UserDefaults(suiteName: appGroupIdentifier)?.set(Date(), forKey: key)
    }

    public static func lastActive(appGroupIdentifier: String) -> Date? {
        UserDefaults(suiteName: appGroupIdentifier)?.object(forKey: key) as? Date
    }
}

/// Hands-free handoff for surfaces that can't reach the app's model directly — the
/// Shortcuts / Action Button / Siri intent, the Control Center / Lock Screen
/// control, and the Home Screen widget buttons. Each records a pending request
/// here; the app honors it the next time it becomes active (see HexIOSApp), which
/// avoids a cold-launch race. Pure App Group / UserDefaults, so it's safe to call
/// from any process/actor.
public enum PendingAppAction {
    private static let startSessionKey = "hex.pendingStartSession"
    private static let recordNoteKey = "hex.pendingRecordNote"
    private static let openKeyboardSettingsKey = "hex.pendingOpenKeyboardSettings"

    private static func request(_ key: String, _ appGroupIdentifier: String) {
        UserDefaults(suiteName: appGroupIdentifier)?.set(true, forKey: key)
    }

    /// Returns true (and clears the flag) if `key` was set.
    private static func consume(_ key: String, _ appGroupIdentifier: String) -> Bool {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        guard defaults?.bool(forKey: key) == true else { return false }
        defaults?.set(false, forKey: key)
        return true
    }

    /// Start a keyboard Flow Session (Control Center / Action Button / Siri).
    public static func requestStartSession(appGroupIdentifier: String = HexAppGroup.identifier) {
        request(startSessionKey, appGroupIdentifier)
    }

    public static func consumeStartSession(appGroupIdentifier: String = HexAppGroup.identifier) -> Bool {
        consume(startSessionKey, appGroupIdentifier)
    }

    /// Start recording a new in-app note (Home Screen widget mic button).
    public static func requestRecordNote(appGroupIdentifier: String = HexAppGroup.identifier) {
        request(recordNoteKey, appGroupIdentifier)
    }

    public static func consumeRecordNote(appGroupIdentifier: String = HexAppGroup.identifier) -> Bool {
        consume(recordNoteKey, appGroupIdentifier)
    }

    /// Open iOS keyboard settings to enable/disable the Voco keyboard (Home Screen
    /// widget status pill). iOS exposes no API to toggle a keyboard directly, so the
    /// best we can do is jump the user to the page where they turn it on or off.
    public static func requestOpenKeyboardSettings(appGroupIdentifier: String = HexAppGroup.identifier) {
        request(openKeyboardSettingsKey, appGroupIdentifier)
    }

    public static func consumeOpenKeyboardSettings(appGroupIdentifier: String = HexAppGroup.identifier) -> Bool {
        consume(openKeyboardSettingsKey, appGroupIdentifier)
    }
}

/// Standard filenames inside the App Group container.
public enum IPCFile {
    public static let result = "dictation-result.json"
    public static let session = "dictation-session.json"
    public static let meter = "dictation-meter.bin"
}

/// Convenience bundle of the two mailboxes for a given App Group container.
public struct KeyboardIPC: Sendable {
    public let resultMailbox: AppGroupMailbox<DictationResult>
    public let sessionMailbox: AppGroupMailbox<DictationSessionState>

    public init?(appGroupIdentifier: String) {
        guard let dir = AppGroupMailbox<DictationResult>.appGroupDirectory(appGroupIdentifier) else {
            return nil
        }
        self.init(directory: dir)
    }

    public init(directory: URL) {
        self.resultMailbox = AppGroupMailbox(directory: directory, filename: IPCFile.result)
        self.sessionMailbox = AppGroupMailbox(directory: directory, filename: IPCFile.session)
    }
}
