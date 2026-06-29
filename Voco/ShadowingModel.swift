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
import VocoCore
import Observation
import os
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

    /// Rolling mic input levels (0…1) for the live recording waveform, mirroring
    /// `DictationModel`. Empty unless actively recording.
    private(set) var levels: [CGFloat] = []
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    // MARK: - CI-11 closed-loop GOP re-scoring

    /// Per-phoneme comparison of the latest attempt against the previous one — the
    /// closed loop. Non-nil only when the pronunciation model is present *and* the
    /// learner has recorded at least a second attempt to compare against. UI shows
    /// it on top of the ASR pass/fail; without it, today's behavior is unchanged.
    private(set) var gopComparison: ShadowingGOP.Comparison?

    /// The most recent attempt's per-phoneme GOP, kept as the reference for the
    /// *next* attempt's deltas. Nil until the first model-scored attempt lands.
    private var lastAttemptScores: PronunciationResult?

    /// The latest scored attempt's full per-phoneme GOP — "your pronunciation" of
    /// the practiced phrase. Non-nil whenever the pronunciation model produced a
    /// result, *including the very first attempt* (when `gopComparison` is still
    /// nil because there's nothing to compare against yet). Lets the result screen
    /// show a per-sound breakdown from the first try, with progress deltas layered
    /// on from the second try onward.
    private(set) var attemptScores: PronunciationResult?

    /// Whether the on-device pronunciation model + dictionary are available. When
    /// false we skip GOP re-scoring entirely and keep the ASR-match result.
    var pronunciationAvailable: Bool { PronunciationAssets.ready }

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
        gopComparison = nil
        attemptScores = nil
        do {
            _ = try recorder.start()
            phase = .recording
            startMetering()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAndScore() async {
        stopMetering()
        guard let url = recorder.stop() else { phase = .idle; return }
        phase = .transcribing
        do {
            let text = try await transcription.transcribe(url, modelName, DecodingOptions()) { _ in }
            heard = text
            score = ShadowingScorer.match(target: target, spoken: text)
            // CI-11: when the phoneme model is present, re-score this attempt and
            // surface per-phoneme deltas vs. the previous attempt (the closed loop).
            await rescoreGOP(attemptURL: url)
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// CI-11 — run the #57 pronunciation pipeline on the attempt audio against the
    /// practiced phrase and compare it to the previous attempt, producing the
    /// per-phoneme deltas (/θ/ red→green) shown on top of the ASR pass/fail.
    ///
    /// Gated on `PronunciationAssets.ready`: with no model, `gopComparison` stays
    /// nil and the result keeps today's ASR-match behavior. The first scored attempt
    /// only establishes the reference; deltas appear from the second attempt on.
    private func rescoreGOP(attemptURL: URL) async {
        guard PronunciationAssets.ready else { return }
        let phrase = target
        let reference = lastAttemptScores
        let scored: PronunciationResult? = await Task.detached(priority: .userInitiated) {
            guard let modelURL = PronunciationAssets.model(),
                  let vocabURL = PronunciationAssets.vocab(),
                  let dictURL = PronunciationAssets.cmudict(),
                  let analyzer = PronunciationAnalyzer(modelURL: modelURL, vocabURL: vocabURL, cmudictURL: dictURL)
            else { return nil }
            do {
                let samples = try PhonemeRecognizer.loadSamples(url: attemptURL)
                return try analyzer.analyze(samples: samples, transcript: phrase)
            } catch {
                HexLog.pronunciation.error("shadowing GOP re-score failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value

        guard let scored else { return }
        // "Your pronunciation" for this attempt — available from the first try.
        attemptScores = scored
        if let reference {
            gopComparison = ShadowingGOP.compare(target: reference, attempt: scored)
        }
        lastAttemptScores = scored
    }

    // MARK: - Waveform metering

    /// Poll the recorder's input level into a rolling buffer (20 Hz) so the mic
    /// hero shows the learner's actual voice, matching the dictation waveform.
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
