//
//  KeyboardViewController.swift
//  HexIOSKeyboard
//
//  Mic-centric dictation keyboard. The keyboard itself never records (iOS blocks
//  mic access in keyboard extensions); tapping the mic bounces to the host app
//  via a custom URL, the host app records + transcribes and writes the result to
//  the shared App Group mailbox, and on returning here we insert it.
//
//  The keys are rendered by KeyboardKit (we subclass `KeyboardInputViewController`
//  and hand it `HexKeyboardRootView`). KeyboardKit owns all typing through the
//  text document proxy; this controller owns only the dictation/IPC engine and
//  the Hex toolbar's actions.
//

import VocoCore
import KeyboardKit
import SwiftUI
import UIKit
import WidgetKit

final class KeyboardViewController: KeyboardInputViewController {
    private let ipc = KeyboardIPC(appGroupIdentifier: HexAppGroup.identifier)

    /// Hex's own dictation state machine. Named `hexState` because the KeyboardKit
    /// base class already exposes its own `state` (`Keyboard.State`).
    private let hexState = KeyboardState()

    /// Toolbar callbacks, built once in `viewDidLoad`.
    private var actions: KeyboardActions = .noop

    private var lastInsertedID: UUID?
    private var resultObserver: DarwinSignalObserver?
    private var observerTask: Task<Void, Never>?
    private var isCapturing = false

    /// Drives the once-per-second `state.clock` tick so the "MM:SS left" pill and
    /// the session-expiry phase update live without a re-bounce.
    private var clockTimer: Timer?

    /// Auto-clears the brief "Inserted" confirmation (the .inserting state).
    private var insertConfirmationTask: Task<Void, Never>?

    /// Don't insert a result older than this (avoids surfacing a stale, never-consumed transcript).
    private let resultFreshnessWindow: TimeInterval = 300

    // MARK: - KeyboardKit setup

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up KeyboardKit for the Hex keyboard app. We don't hand it our App
        // Group (we run our own IPC) or a Pro license — this is the free tier.
        setup(for: .hex) { _ in }

        hexState.needsNextKeyboard = needsInputModeSwitchKey
        hexState.hasFullAccess = hasFullAccess
        actions = makeActions()
    }

    /// Called when KeyboardKit needs to (re)build the keyboard view. We hand it the
    /// native `KeyboardView` (via `HexKeyboardRootView`) with the Hex toolbar slot.
    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [weak self] controller in
            HexKeyboardRootView(
                keyboardState: controller.state,
                services: controller.services,
                hexState: self?.hexState ?? KeyboardState(),
                actions: self?.actions ?? .noop
            )
        }
    }

    private func makeActions() -> KeyboardActions {
        KeyboardActions(
            onMic: { [weak self] in self?.handleMicTap() },
            onCancelDictation: { [weak self] in self?.handleMicTap() },
            onSettings: { [weak self] in self?.openHostApp(path: "settings") }
        )
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hexState.hasFullAccess = hasFullAccess
        // With Full Access we can touch the App Group — record presence + signal
        // so the host app's onboarding can confirm the keyboard is set up.
        if hasFullAccess {
            KeyboardPresence.markActive(appGroupIdentifier: HexAppGroup.identifier)
            DarwinSignal.post(.keyboardActive)
            // Flip the Home widget's "Enable keyboard" status to "Keyboard on".
            WidgetCenter.shared.reloadTimelines(ofKind: "HexWidgets")
        }
        refreshSessionState()
        insertPendingResult()
        startObservingResults()
        startClock()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        observerTask?.cancel()
        observerTask = nil
        resultObserver = nil
        clockTimer?.invalidate()
        clockTimer = nil
        insertConfirmationTask?.cancel()
        insertConfirmationTask = nil
    }

    /// One cheap timer drives the live countdown + expiry transition. No model,
    /// no audio — keeps the extension memory-light.
    private func startClock() {
        clockTimer?.invalidate()
        // The timer is scheduled on `RunLoop.main`, so it already fires on the main
        // thread — assert the isolation synchronously instead of hopping through a
        // Task each tick (which captured `self` across a concurrency boundary).
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hexState.clock = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        hexState.needsNextKeyboard = needsInputModeSwitchKey
    }

    // MARK: - Actions

    /// If a Flow Session is active, toggle capture in place (no bounce). Otherwise
    /// bounce once to the host app to start a session.
    private func handleMicTap() {
        guard hasFullAccess else {
            hexState.statusText = "Enable Full Access (Settings ▸ Keyboards) to dictate."
            return
        }
        // Any user-initiated tap clears a stale error/confirmation so the UI
        // reflects the action they just took.
        hexState.errorMessage = nil
        hexState.justInserted = false
        // Re-read liveness fresh on every tap; a session can have died (app
        // crashed/suspended) since we last refreshed, leaving a stale "active" flag.
        let session = currentSession()
        let usable = session?.isUsable(at: Date()) == true
        hexState.sessionActive = usable
        hexState.sessionExpiresAt = usable ? session?.expiresAt : nil
        if usable {
            toggleCapture()
        } else {
            // Session is dead/stale — reset any stuck capturing state and bounce
            // to start a fresh one instead of posting into the void.
            isCapturing = false
            hexState.isCapturing = false
            startSessionBounce()
        }
    }

    private func toggleCapture() {
        if isCapturing {
            DarwinSignal.post(.captureStop)
            isCapturing = false
            hexState.statusText = "Transcribing…"
        } else {
            DarwinSignal.post(.captureStart)
            isCapturing = true
            hexState.statusText = "Listening… tap to stop"
        }
        hexState.isCapturing = isCapturing
    }

    private func startSessionBounce() {
        guard let url = URL(string: "hexkb://startSession") else { return }
        hexState.statusText = "Starting session in Hex…"
        guard let application = firstUIApplicationInResponderChain() else {
            hexState.errorMessage = "Couldn't reach Hex. Open the app once, then try again."
            hexState.statusText = "Couldn't reach the app (no UIApplication in chain)."
            return
        }
        application.open(url, options: [:]) { [weak self] success in
            if !success {
                self?.hexState.errorMessage = "iOS blocked opening Hex."
                self?.hexState.statusText = "iOS blocked opening Hex."
            }
        }
    }

    /// Open the Hex app at a given path (e.g. "settings") from the toolbar. Best
    /// effort — requires Full Access and a UIApplication in the responder chain.
    private func openHostApp(path: String) {
        guard hasFullAccess, let url = URL(string: "hexkb://\(path)") else { return }
        firstUIApplicationInResponderChain()?.open(url, options: [:], completionHandler: nil)
    }

    private func currentSession() -> DictationSessionState? {
        guard let ipc else { return nil }
        return try? ipc.sessionMailbox.read()
    }

    // MARK: - Result + session signals

    private func startObservingResults() {
        guard observerTask == nil else { return }
        let observer = DarwinSignalObserver([.resultReady, .sessionChanged])
        resultObserver = observer
        observerTask = Task { [weak self] in
            for await signal in observer.stream() {
                await MainActor.run {
                    switch signal {
                    case .resultReady: self?.insertPendingResult()
                    case .sessionChanged: self?.refreshSessionState()
                    default: break
                    }
                }
            }
        }
    }

    private func refreshSessionState() {
        let session = currentSession()
        let active = session?.isUsable(at: Date()) == true
        hexState.sessionActive = active
        hexState.sessionExpiresAt = active ? session?.expiresAt : nil
        if !active {
            isCapturing = false
            hexState.isCapturing = false
        }
    }

    private func insertPendingResult() {
        guard hasFullAccess, let ipc, let result = try? ipc.resultMailbox.read() else { return }
        guard result.id != lastInsertedID else { return }
        guard Date().timeIntervalSince(result.createdAt) < resultFreshnessWindow else {
            ipc.resultMailbox.clear()
            return
        }
        textDocumentProxy.insertText(result.text)
        lastInsertedID = result.id
        ipc.resultMailbox.clear()
        isCapturing = false
        hexState.isCapturing = false
        hexState.errorMessage = nil
        hexState.statusText = hexState.sessionActive ? "Inserted — tap to dictate again." : "Inserted."
        flashInsertedConfirmation()
    }

    /// Shows the brief ".inserting" confirmation state, then returns to idle.
    private func flashInsertedConfirmation() {
        insertConfirmationTask?.cancel()
        hexState.justInserted = true
        insertConfirmationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.hexState.justInserted = false }
        }
    }

    // MARK: - Bounce

    /// Opens the host app from the extension by finding `UIApplication` in the
    /// responder chain and calling the modern `open(_:options:completionHandler:)`.
    /// (The old `openURL:` selector hack no-ops on recent iOS.) Unsupported by
    /// Apple but the standard way keyboards launch their container; requires Full
    /// Access. Returns whether a UIApplication was found. Isolated here so there's
    /// one place to fix if a future iOS changes the behavior.
    private func firstUIApplicationInResponderChain() -> UIApplication? {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication { return application }
            responder = current.next
        }
        return nil
    }
}

// MARK: - KeyboardApp

private extension KeyboardApp {
    /// The Hex keyboard app. Minimal on purpose: no App Group (we run our own
    /// `KeyboardIPC`) and no Pro license key (free tier).
    static var hex: KeyboardApp {
        .init(name: "Hex")
    }
}
