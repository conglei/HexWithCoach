//
//  DictationModel.swift
//  HexIOS
//
//  Observable orchestrator: model loading, mic permission, record → transcribe →
//  history, and the keyboard Flow Session. Transcription uses the shared engine
//  (TranscriptionClient) so iOS gets Whisper + Parakeet, matching macOS.
//

import ActivityKit
import Dependencies
import Foundation
import VocoCore
import Observation
import os
import SwiftData
import WhisperKit

/// What produced a transcript — the coaching corpus distinguishes guided in-app
/// notes from natural cross-app dictation (Review/Coach design §13, RC-0).
enum TranscriptKind: String, Codable, Equatable {
    case dictation  // cross-app / keyboard Flow Session
    case note       // in-app capture from the app

    var label: String {
        switch self {
        case .dictation: "Dictation"
        case .note: "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation: "keyboard"
        case .note: "note.text"
        }
    }
}

/// How long a Flow Session stays hot after the last activity (product spec: 5/15/60/never).
enum SessionLength: Int, CaseIterable, Identifiable {
    case five = 5
    case fifteen = 15
    case sixty = 60
    case never = 0

    var id: Int { rawValue }
    /// nil = no timeout ("never").
    var duration: TimeInterval? { self == .never ? nil : TimeInterval(rawValue * 60) }
    var label: String { self == .never ? "Never" : "\(rawValue) min" }
}

@MainActor
@Observable
final class DictationModel {
    enum ModelState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum Phase: Equatable {
        case idle
        case recording
        case paused
        case transcribing
    }

    /// Default transcription model. Parakeet v3 (multilingual) matches the macOS
    /// default; the shared engine also supports Whisper sizes (user-selectable later).
    let modelName = ParakeetModel.multilingualV3.identifier

    private(set) var modelState: ModelState = .loading
    /// 0…1 progress of the first-run model download/load (Parakeet is large).
    private(set) var modelProgress: Double = 0
    private(set) var phase: Phase = .idle
    /// Rolling mic input levels (0…1) for the recording waveform.
    private(set) var levels: [CGFloat] = []

    /// SwiftData context for persisting transcripts (history survives relaunch
    /// and syncs via CloudKit). The UI reads transcripts via @Query.
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        if let raw = UserDefaults(suiteName: HexAppGroup.identifier)?.object(forKey: Self.sessionLengthKey) as? Int,
           let value = SessionLength(rawValue: raw) {
            sessionLength = value
        }
    }

    /// The note just saved from in-app capture, so Home can open it automatically
    /// once the recording sheet dismisses. Cleared by the consumer.
    var lastSavedNote: TranscriptEntry?

    /// Capture hook (CI-7): invoked in the background after any transcript is saved,
    /// so the always-on objective lane (and the gated LLM lane) run automatically
    /// without a manual button. Wired by the app to `CoachService.autoAnalyzeOnCapture`.
    /// Kept as a closure so `DictationModel` stays decoupled from `CoachService`.
    var onTranscriptSaved: ((TranscriptEntry) async -> Void)?

    /// Persist a transcript, retaining its audio (moved into the App Group) so the
    /// Coach corpus has both text and audio.
    private func save(text: String, kind: TranscriptKind, audioURL: URL?, words: [HexCore.WordTiming]? = nil, surface: Bool = true) {
        // Incognito (RC-8): dictation still inserts text, but we keep nothing —
        // no transcript, no audio.
        guard !CapturePreferences.incognito else {
            if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
            return
        }
        let filename = audioURL.flatMap { AudioStore.persist($0) }
        let entry = TranscriptEntry(text: text, date: Date(), kind: kind, audioFilename: filename)
        entry.wordTimings = words
        modelContext.insert(entry)
        try? modelContext.save()
        // In-app notes open straight into their detail; dictation snippets just
        // get inserted into the host app, so don't surface those. Recovered notes
        // (`surface: false`) appear in History silently rather than yanking the
        // user into a detail view on launch.
        if kind == .note, surface { lastSavedNote = entry }
        // Automatic two-lane analysis (CI-7): fire-and-forget in the background so
        // the save path stays snappy and coaching "just appears". Applies to both
        // notes and Flow Session dictations — the whole corpus is coachable.
        if let onTranscriptSaved {
            Task { await onTranscriptSaved(entry) }
        }
    }
    /// When the current note *span* started recording (reset on each resume). Used
    /// with `accumulatedDuration` to drive the cumulative recording timer.
    private(set) var recordingStartedAt: Date?
    /// Recording time banked from spans before the current one (so the timer keeps
    /// counting across pause/resume instead of restarting each resume).
    private(set) var accumulatedDuration: TimeInterval = 0
    /// Finalized audio spans of the in-progress note (one per record→pause), stored
    /// in the crash-safe Drafts dir and concatenated on "Done".
    private var noteSegments: [URL] = []
    /// True while a note interrupted by an app kill/crash is being transcribed in
    /// the background at launch (gates starting a new note).
    private(set) var isRecovering = false
    var errorMessage: String?

    /// Cumulative elapsed recording time across pause/resume, for the timer.
    var currentElapsed: TimeInterval {
        let live = (phase == .recording) ? Date().timeIntervalSince(recordingStartedAt ?? Date()) : 0
        return accumulatedDuration + live
    }

    /// Set after a keyboard session starts, prompting the user to swipe back to
    /// their app where the keyboard will insert dictated text.
    private(set) var awaitingSwipeBack = false

    /// True while a session is being started — notably during the one-time
    /// ~18s cold load of the Parakeet model after a keyboard bounce. Drives the
    /// "Preparing dictation…" state so the bounce isn't a blank wait.
    private(set) var isStartingSession = false

    /// Whether a continuous Flow Session is active (mic stays hot; keyboard can
    /// dictate without re-bouncing).
    private(set) var sessionActive = false
    private(set) var sessionExpiresAt: Date?

    /// Session auto-ends this long after the last activity (persisted in the App Group).
    var sessionLength: SessionLength = .fifteen {
        didSet { UserDefaults(suiteName: HexAppGroup.identifier)?.set(sessionLength.rawValue, forKey: Self.sessionLengthKey) }
    }
    @ObservationIgnored private static let sessionLengthKey = "hex.sessionLengthMinutes"

    private let recorder = AudioRecorder()
    @ObservationIgnored @Dependency(\.transcription) private var transcription
    private let ipc = KeyboardIPC(appGroupIdentifier: HexAppGroup.identifier)
    private var prepareTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?

    private let sessionEngine = SessionAudioEngine()
    private var captureObserverTask: Task<Void, Never>?
    private var captureObserver: DarwinSignalObserver?
    private var sessionTimeoutTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var activity: Activity<FlowSessionAttributes>?
    private var sessionCaptureURL: URL?

    /// Whether a brand-new note can be started (gates the Home mic + pull-to-dictate).
    /// Only when fully idle — a paused note is still in progress, and we don't start
    /// one over an in-flight crash recovery.
    var canRecord: Bool { modelState == .ready && phase == .idle && !isRecovering }

    var recordButtonTitle: String {
        switch phase {
        case .idle: "Start Dictation"
        case .recording: "Pause"
        case .paused: "Resume"
        case .transcribing: "Transcribing…"
        }
    }

    /// Load the model + request mic permission. Idempotent: callers (the view's
    /// `.task` and the keyboard bounce) share one underlying run, so a cold launch
    /// via `hexkb://` doesn't kick off a second model load.
    func prepare() async {
        if let prepareTask { return await prepareTask.value }
        let task = Task { await self.runPrepare() }
        prepareTask = task
        await task.value
    }

    private func runPrepare() async {
        _ = await recorder.requestPermission()
        do {
            try await transcription.downloadModel(modelName) { [weak self] progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in self?.modelProgress = fraction }
            }
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    /// The Home mic button: start a new note when idle, finish it when recording or
    /// paused. (Pause/resume have their own controls in the recording screen.)
    func toggleRecording() async {
        switch phase {
        case .idle: await startRecording()
        case .recording, .paused: await finishRecording()
        case .transcribing: break
        }
    }

    private func startRecording() async {
        guard modelState == .ready else { return }
        guard await recorder.requestPermission() else {
            errorMessage = AudioRecorder.RecorderError.permissionDenied.localizedDescription
            return
        }
        do {
            _ = try recorder.start()
            noteSegments = []
            accumulatedDuration = 0
            recordingStartedAt = Date()
            phase = .recording
            startMetering()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pause the in-progress note. The current span is stopped, finalized, and moved
    /// into crash-safe storage immediately, so a crash/kill while paused can't lose
    /// it. Resuming records a fresh span that's concatenated on "Done".
    func pauseRecording() {
        guard phase == .recording else { return }
        stopMetering()
        if let startedAt = recordingStartedAt {
            accumulatedDuration += Date().timeIntervalSince(startedAt)
        }
        recordingStartedAt = nil
        if let url = recorder.stop() { bankSpan(url) }
        phase = .paused
    }

    /// Resume a paused note by recording a new span (concatenated with the rest on
    /// "Done"). Mic permission was already granted when the note started.
    func resumeRecording() {
        guard phase == .paused else { return }
        do {
            _ = try recorder.start()
            recordingStartedAt = Date()
            phase = .recording
            startMetering()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Finish the note: finalize the current span, concatenate every span into one
    /// clip, transcribe, and save. Works from either recording or paused.
    func finishRecording() async {
        guard phase == .recording || phase == .paused else { return }
        stopMetering()
        if phase == .recording {
            if let startedAt = recordingStartedAt {
                accumulatedDuration += Date().timeIntervalSince(startedAt)
            }
            if let url = recorder.stop() { bankSpan(url) }
        }
        recordingStartedAt = nil
        let segments = noteSegments
        noteSegments = []
        guard !segments.isEmpty else { phase = .idle; return }

        phase = .transcribing
        defer { phase = .idle }

        // One span → use it directly; multiple spans → concatenate into one clip.
        let clip: URL
        if segments.count == 1 {
            clip = segments[0]
        } else {
            clip = (try? AudioStore.concatenate(segments)) ?? segments[0]
        }

        do {
            let result = try await transcription.transcribeWithTimings(clip, modelName, DecodingOptions()) { _ in }
            // Drop the now-redundant spans (keep `clip` for save()).
            cleanupDraftSegments(segments, except: clip)
            guard !result.text.isEmpty else { try? FileManager.default.removeItem(at: clip); return }
            save(text: result.text, kind: .note, audioURL: clip, words: result.words)
        } catch {
            // Keep the spans on failure so the recorded audio isn't lost.
            errorMessage = error.localizedDescription
        }
    }

    /// Discard the in-progress note (any span) without transcribing. Used by the
    /// "Cancel" control.
    func cancelRecording() {
        guard phase == .recording || phase == .paused else { return }
        stopMetering()
        if let url = recorder.stop() { try? FileManager.default.removeItem(at: url) }
        cleanupDraftSegments(noteSegments, except: nil)
        noteSegments = []
        accumulatedDuration = 0
        recordingStartedAt = nil
        phase = .idle
    }

    private func cleanupDraftSegments(_ urls: [URL], except keep: URL?) {
        for url in urls where url != keep {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Bank a finalized span for the current note. Normally we move it into the
    /// crash-safe Drafts dir so an app kill while paused can't lose it; in incognito
    /// the user wants nothing retained, so we keep it only in temp (ephemeral) and
    /// it's never eligible for recovery.
    private func bankSpan(_ tempURL: URL) {
        if CapturePreferences.incognito {
            noteSegments.append(tempURL)
        } else if let persisted = AudioStore.persistDraftSegment(tempURL) {
            noteSegments.append(persisted)
        }
    }

    /// Automatic crash recovery: if an interrupted note left spans on disk (app
    /// killed while paused, or a transcription that never completed), transcribe
    /// and save them as a note on the next launch — no user action required. Runs
    /// silently; the recovered note simply appears in History.
    func recoverInterruptedNote() async {
        guard phase == .idle, !isRecovering else { return }
        let spans = AudioStore.orphanedDraftSegments()
        guard !spans.isEmpty else { return }

        isRecovering = true
        defer { isRecovering = false }

        if modelState != .ready { await prepare() }
        // Can't transcribe without a model — leave the spans for a later launch.
        guard modelState == .ready else { return }

        let clip: URL = spans.count == 1 ? spans[0] : ((try? AudioStore.concatenate(spans)) ?? spans[0])
        do {
            let result = try await transcription.transcribeWithTimings(clip, modelName, DecodingOptions()) { _ in }
            cleanupDraftSegments(spans, except: clip)
            guard !result.text.isEmpty else { try? FileManager.default.removeItem(at: clip); return }
            save(text: result.text, kind: .note, audioURL: clip, words: result.words, surface: false)
            HexLog.transcription.notice("Recovered an interrupted note (\(spans.count) span(s))")
        } catch {
            // Keep the spans so the next launch can retry; don't surface an error.
            HexLog.transcription.error("Interrupted-note recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Waveform metering

    private func startMetering() {
        let barCount = 32
        levels = Array(repeating: 0, count: barCount)
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.phase == .recording else { break }
                var next = self.levels
                next.removeFirst()
                next.append(self.recorder.level())
                self.levels = next
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        levels = []
    }

    func dismissSwipeBackHint() {
        awaitingSwipeBack = false
    }

    // MARK: - Continuous Flow Session

    /// Entry point for the keyboard's session bounce (`hexkb://startSession`):
    /// start the continuous engine in the foreground, publish session state, and
    /// listen for capture signals from the keyboard. The user then swipes back and
    /// dictates in place — no further bounces until the session ends.
    func startKeyboardSession() async {
        awaitingSwipeBack = false
        isStartingSession = true
        defer { isStartingSession = false }
        if modelState != .ready { await prepare() }
        guard modelState == .ready else { return }
        guard await recorder.requestPermission() else {
            errorMessage = AudioRecorder.RecorderError.permissionDenied.localizedDescription
            return
        }
        do {
            if !sessionEngine.isRunning { try sessionEngine.start() }
            beginObservingCaptures()
            extendSession()
            startHeartbeat()
            startActivity()
            awaitingSwipeBack = true
        } catch {
            errorMessage = error.localizedDescription
            endSession()
        }
    }

    func endSession() {
        sessionTimeoutTask?.cancel(); sessionTimeoutTask = nil
        captureObserverTask?.cancel(); captureObserverTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        captureObserver = nil
        sessionEngine.stop()
        sessionCaptureURL = nil
        sessionActive = false
        sessionExpiresAt = nil
        awaitingSwipeBack = false
        publishSessionState(active: false, expiresAt: nil)
        endActivity()
    }

    /// Refresh the session heartbeat while the app is genuinely alive, so the
    /// keyboard can detect a crash/suspension (heartbeat goes stale) and bounce
    /// instead of posting capture signals into the void.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.sessionActive else { break }
                self.publishSessionState(active: true, expiresAt: self.sessionExpiresAt, notify: false)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func beginObservingCaptures() {
        guard captureObserverTask == nil else { return }
        let observer = DarwinSignalObserver([.captureStart, .captureStop, .endSession])
        captureObserver = observer
        captureObserverTask = Task { [weak self] in
            for await signal in observer.stream() {
                await self?.handleCapture(signal)
            }
        }
    }

    private func handleCapture(_ signal: IPCSignal) async {
        switch signal {
        case .captureStart:
            guard sessionCaptureURL == nil else { return }
            // iOS may have killed our backgrounded engine (interruption / route
            // change). Verify it's actually live before capturing so we don't
            // record an empty file. If it can't be recovered, end the session so
            // the keyboard re-bounces for a fresh one instead of capturing silence.
            guard sessionEngine.ensureRunning() else {
                HexLog.recording.error("Flow Session capture aborted: audio engine could not be restarted")
                endSession()
                return
            }
            sessionCaptureURL = try? sessionEngine.beginCapture()
            extendSession()
            updateActivity(capturing: true)
        case .captureStop:
            guard sessionCaptureURL != nil else { return }
            let url = sessionEngine.endCapture()
            sessionCaptureURL = nil
            updateActivity(capturing: false)
            if let url { await transcribeSessionSnippet(url) }
        case .endSession:
            endSession()
        default:
            break
        }
    }

    // MARK: - Live Activity

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let state = FlowSessionAttributes.ContentState(endsAt: sessionExpiresAt, isCapturing: false)
        activity = try? Activity.request(
            attributes: FlowSessionAttributes(),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    private func updateActivity(capturing: Bool) {
        guard let activity else { return }
        let state = FlowSessionAttributes.ContentState(endsAt: sessionExpiresAt, isCapturing: capturing)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func endActivity() {
        guard let activity else { return }
        let state = FlowSessionAttributes.ContentState(endsAt: nil, isCapturing: false)
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private func transcribeSessionSnippet(_ url: URL) async {
        do {
            let text = try await transcription.transcribe(url, modelName, DecodingOptions()) { _ in }
            guard !text.isEmpty else { try? FileManager.default.removeItem(at: url); return }
            save(text: text, kind: .dictation, audioURL: url)
            if let ipc {
                try? ipc.resultMailbox.write(DictationResult(text: text, createdAt: Date()))
                DarwinSignal.post(.resultReady)
            }
        } catch {
            // Background snippet failures shouldn't surface a modal alert in the
            // app the user returns to later — log instead. (The user dictates from
            // another app; a "Something went wrong" alert here is confusing and
            // out of context.)
            HexLog.transcription.error("Flow Session snippet transcription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// (Re)set the inactivity timeout and republish the session state.
    private func extendSession() {
        sessionActive = true
        sessionTimeoutTask?.cancel()

        guard let duration = sessionLength.duration else {
            // "Never": keep the session hot with no auto-timeout.
            sessionExpiresAt = nil
            sessionTimeoutTask = nil
            publishSessionState(active: true, expiresAt: nil)
            return
        }

        let expires = Date().addingTimeInterval(duration)
        sessionExpiresAt = expires
        publishSessionState(active: true, expiresAt: expires)
        sessionTimeoutTask = Task { [weak self] in
            let seconds = expires.timeIntervalSinceNow
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.endSession()
        }
    }

    private func publishSessionState(active: Bool, expiresAt: Date?, notify: Bool = true) {
        guard let ipc else { return }
        // heartbeat defaults to now in the initializer.
        try? ipc.sessionMailbox.write(DictationSessionState(isActive: active, expiresAt: expiresAt))
        if notify { DarwinSignal.post(.sessionChanged) }
    }
}
