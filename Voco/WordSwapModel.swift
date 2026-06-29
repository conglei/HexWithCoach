//
//  WordSwapModel.swift
//  Voco
//
//  CF-2 — the runtime for the `wordSwap` drill. Mirrors `ShadowingModel`'s
//  record→transcribe shape (same `AudioRecorder` + on-device `transcription`
//  dependency) but, instead of a GOP/ASR-match pronunciation grade, it judges
//  whether the learner *produced* a more-natural word/phrase using the pure
//  `WordSwapJudge` (VocoCore). The judge is on-device, so production never blocks
//  on the network — the drill works with no API key.
//
//  Phases mirror the drill's flow: a quick recognition warm-up (the view shows the
//  before → after), then production (record → transcribe → judge → feedback).
//

import AVFoundation
import Dependencies
import Foundation
import VocoCore
import Observation
import WhisperKit

@MainActor
@Observable
final class WordSwapModel {
    enum Phase: Equatable { case warmUp, idle, recording, transcribing, done }

    /// The drill content (target rewrite, original span, lens copy).
    let drill: WordSwapDrill
    private(set) var phase: Phase = .warmUp
    /// What the learner produced (their transcribed attempt).
    private(set) var heard: String = ""
    /// The judge's latest verdict, set when an attempt finishes.
    private(set) var result: WordSwapJudge.Result?
    var errorMessage: String?

    /// Rolling mic input levels (0…1) for the live recording waveform.
    private(set) var levels: [CGFloat] = []
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    private let modelName = ParakeetModel.multilingualV3.identifier
    private let recorder = AudioRecorder()
    private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored @Dependency(\.transcription) private var transcription

    init(drill: WordSwapDrill) { self.drill = drill }

    // MARK: - Derived

    /// The native phrasing the learner is being nudged toward.
    var targetPhrase: String { drill.targetPhrase }
    /// What the learner originally said (the "before"), if any.
    var originalSpan: String? { drill.content.originalSpan }
    /// 0…1 score of the latest attempt (0 until one finishes).
    var score: Double { result?.value ?? 0 }
    /// Whether the latest attempt cleared the bar.
    var isWin: Bool { result?.isWin ?? false }

    /// Move from the recognition warm-up into production.
    func beginProduction() {
        guard phase == .warmUp else { return }
        phase = .idle
    }

    #if DEBUG
    /// DEBUG-only: judge a canned production and jump to the result screen, so a
    /// seeded screenshot / QA run can verify the scoring + verdict UI without
    /// driving the mic. No effect in release; not called from production code.
    func debugInjectProduction(_ text: String) {
        heard = text
        result = drill.judge(production: text)
        phase = .done
    }
    #endif

    /// Speak the native target so the learner can hear the model phrasing.
    func speakTarget() { speak(targetPhrase) }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        synthesizer.speak(utterance)
    }

    // MARK: - Record → transcribe → judge

    func toggleRecord() async {
        switch phase {
        case .idle, .done: await startRecording()
        case .recording: await stopAndJudge()
        case .warmUp, .transcribing: break
        }
    }

    private func startRecording() async {
        guard await recorder.requestPermission() else {
            errorMessage = "Microphone access is needed to practice."
            return
        }
        heard = ""
        result = nil
        do {
            _ = try recorder.start()
            phase = .recording
            startMetering()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAndJudge() async {
        stopMetering()
        guard let url = recorder.stop() else { phase = .idle; return }
        phase = .transcribing
        do {
            let text = try await transcription.transcribe(url, modelName, DecodingOptions()) { _ in }
            heard = text
            // On-device judge — no network, graceful with no API key.
            result = drill.judge(production: text)
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Metering (mirrors ShadowingModel)

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
}

extension WordSwapDrill {
    /// Convenience so the model can judge without re-deriving the target.
    func judge(production: String) -> WordSwapJudge.Result {
        WordSwapJudge.judge(
            production: production,
            target: targetPhrase,
            original: content.originalSpan
        )
    }
}
