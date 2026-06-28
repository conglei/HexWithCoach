//
//  ShadowingModel.swift
//  HexIOS
//
//  RC-4 shadowing: hear the natural phrasing (on-device TTS), then say it back.
//  An on-device ASR pass confirms you produced the phrase (ShadowingScorer). All
//  offline — the optional cloud pronunciation check is a later add. Never a forced
//  gate: reading the rewrite is already valuable.
//

import AVFoundation
import Dependencies
import Foundation
import HexCore
import Observation
import WhisperKit

@MainActor
@Observable
final class ShadowingModel {
    enum Phase: Equatable { case idle, recording, transcribing, done }

    let target: String
    private(set) var phase: Phase = .idle
    private(set) var heard: String = ""
    private(set) var score: Double = 0
    var errorMessage: String?

    private let modelName = ParakeetModel.multilingualV3.identifier
    private let recorder = AudioRecorder()
    private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored @Dependency(\.transcription) private var transcription

    init(target: String) { self.target = target }

    var isSuccess: Bool { score >= ShadowingScorer.matchThreshold }

    /// Speak the target phrase (on-device synthesizer).
    func speak() {
        let utterance = AVSpeechUtterance(string: target)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        // Reset the session so TTS plays out the main speaker, not the earpiece the
        // recording session leaves it routed to (mirrors AudioPlayer's route reset).
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        synthesizer.speak(utterance)
    }

    func toggleRecord() async {
        switch phase {
        case .idle, .done: await startRecording()
        case .recording: await stopAndScore()
        case .transcribing: break
        }
    }

    private func startRecording() async {
        guard await recorder.requestPermission() else {
            errorMessage = "Microphone access is needed to practice."
            return
        }
        heard = ""
        score = 0
        do {
            _ = try recorder.start()
            phase = .recording
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAndScore() async {
        guard let url = recorder.stop() else { phase = .idle; return }
        phase = .transcribing
        do {
            let text = try await transcription.transcribe(url, modelName, DecodingOptions()) { _ in }
            heard = text
            score = ShadowingScorer.match(target: target, spoken: text)
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
        try? FileManager.default.removeItem(at: url)
    }
}
