//
//  MacShadowingModel.swift
//  VocoMac
//
//  MC-R9 — the macOS shadowing engine: the closed practice loop behind a
//  `MacPracticeSessionView` segment. It mirrors the iOS `ShadowingModel`
//  (Voco target) natively on macOS, reusing the shared scorers (`ShadowingScorer`,
//  `ShadowingGOP` in VocoCore) and the macOS transcription + recording paths
//  (`TranscriptionClient` / `RecordingClient`, VocoEngine) — no shared module is
//  touched.
//
//  Phase flow (one per practiced line):
//
//    idle ──speak()──▶ (TTS plays, stays idle) ──record()──▶ recording
//         ◀────────────────────────────────── stopAndScore() ──▶ transcribing ──▶ scored
//
//    • idle:         the target line is shown with "Hear it" (TTS) + a record button.
//    • recording:    the mic is capturing the learner's repeat; a live level meter runs.
//    • transcribing: the clip is being run through on-device ASR.
//    • scored:       ASR match (`ShadowingScorer`) plus, when the phoneme model is
//                    present, per-phoneme GOP deltas vs the previous attempt.
//
//  Scoring + persistence: the ASR match `score` (0…1) is the per-segment score the
//  session writes into the `PracticeAttempt.perSegmentScores` array. The GOP re-score
//  is gated on `MacPronunciationAssets.ready` — a no-op on macOS today (no phoneme
//  model is bundled in the companion app), exactly like MC-R4/MC-R7's objective lane.
//  When a model is side-loaded it produces `gopComparison`/`attemptScores` and a
//  `gopDelta` the session persists onto the attempt; without it, the loop rests on
//  the ASR match and behaves as before.
//

import AVFoundation
import ComposableArchitecture
import Foundation
import Observation
import VocoCore
import WhisperKit

@MainActor
@Observable
final class MacShadowingModel {
    enum Phase: Equatable { case idle, recording, transcribing, scored }

    /// The target line the learner is shadowing.
    let target: String

    private(set) var phase: Phase = .idle
    /// The ASR transcript of the most recent attempt.
    private(set) var heard: String = ""
    /// ASR word-match score (0…1) for the most recent attempt.
    private(set) var score: Double = 0
    var errorMessage: String?

    /// Rolling mic levels (0…1) for the live recording meter; empty unless recording.
    private(set) var levels: [CGFloat] = []
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    // MARK: - Closed-loop GOP (gated on the phoneme model)

    /// Per-phoneme comparison of the latest attempt against the previous one — the
    /// closed loop. Non-nil only when the phoneme model is present *and* a second
    /// attempt exists to compare against. nil (no-op) on macOS today.
    private(set) var gopComparison: ShadowingGOP.Comparison?

    /// The latest scored attempt's full per-phoneme GOP — "your pronunciation" of
    /// the practiced phrase. Non-nil whenever the model produced a result, including
    /// the very first scored attempt.
    private(set) var attemptScores: PronunciationResult?

    /// The previous attempt's GOP, kept as the reference for the *next* attempt's
    /// deltas. nil until the first model-scored attempt lands.
    @ObservationIgnored private var lastAttemptScores: PronunciationResult?

    /// GOP delta (mean per-phoneme improvement) vs. the previous attempt — the value
    /// persisted onto `PracticeAttempt.gopDelta`. nil without a comparison.
    private(set) var gopDelta: Double?

    /// Whether the on-device phoneme model + dictionary are available. False on the
    /// companion app today, so GOP re-scoring is skipped and the ASR result stands.
    var pronunciationAvailable: Bool { MacPronunciationAssets.ready }

    // MARK: - Dependencies (macOS recording + shared ASR)

    @ObservationIgnored @Dependency(\.transcription) private var transcription
    @ObservationIgnored @Dependency(\.recording) private var recording

    @ObservationIgnored @Shared(.hexSettings) private var hexSettings: HexSettings

    /// The synthesizer for "Hear it". Retained so utterances aren't deallocated
    /// mid-speech.
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    init(target: String) { self.target = target }

    /// Whether the most recent attempt cleared the shared match threshold.
    var isSuccess: Bool { score >= ShadowingScorer.matchThreshold }

    // MARK: - Hear it (on-device TTS)

    /// Speak the target line with the on-device synthesizer.
    func speak() {
        let utterance = AVSpeechUtterance(string: target)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(utterance)
    }

    // MARK: - Record + score

    /// Toggle recording: start from idle/scored, stop-and-score while recording.
    func toggleRecord() async {
        switch phase {
        case .idle, .scored: await startRecording()
        case .recording: await stopAndScore()
        case .transcribing: break
        }
    }

    private func startRecording() async {
        guard await recording.requestMicrophoneAccess() else {
            errorMessage = "Microphone access is needed to practice."
            return
        }
        heard = ""
        score = 0
        gopComparison = nil
        attemptScores = nil
        gopDelta = nil
        await recording.startRecording(false)
        phase = .recording
        startMetering()
    }

    private func stopAndScore() async {
        stopMetering()
        let url = await recording.stopRecording()
        phase = .transcribing
        let model = hexSettings.selectedModel
        let language = hexSettings.outputLanguage
        let options = DecodingOptions(
            language: language,
            detectLanguage: language == nil,
            chunkingStrategy: .vad
        )
        do {
            let text = try await transcription.transcribe(url, model, options) { _ in }
            heard = text
            score = ShadowingScorer.match(target: target, spoken: text)
            // Closed-loop GOP re-score — gated; no-op without the phoneme model.
            await rescoreGOP(attemptURL: url)
            phase = .scored
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    /// Run the on-device pronunciation pipeline on the attempt audio against the
    /// practiced phrase and compare it to the previous attempt, producing per-phoneme
    /// deltas. Gated on `MacPronunciationAssets.ready`: with no model this is a no-op
    /// and the result keeps the ASR-match behavior. The first scored attempt only
    /// establishes the reference; deltas appear from the second attempt onward.
    private func rescoreGOP(attemptURL: URL) async {
        guard MacPronunciationAssets.ready else { return }
        let phrase = target
        let reference = lastAttemptScores
        let scored: PronunciationResult? = await Task.detached(priority: .userInitiated) {
            guard let modelURL = MacPronunciationAssets.model(),
                  let vocabURL = MacPronunciationAssets.vocab(),
                  let dictURL = MacPronunciationAssets.cmudict(),
                  let analyzer = PronunciationAnalyzer(modelURL: modelURL, vocabURL: vocabURL, cmudictURL: dictURL)
            else { return nil }
            do {
                let samples = try PhonemeRecognizer.loadSamples(url: attemptURL)
                return try analyzer.analyze(samples: samples, transcript: phrase)
            } catch {
                HexLog.pronunciation.error("Mac shadowing GOP re-score failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value

        guard let scored else { return }
        attemptScores = scored
        if let reference {
            let comparison = ShadowingGOP.compare(target: reference, attempt: scored)
            gopComparison = comparison
            gopDelta = comparison.meanDelta
        }
        lastAttemptScores = scored
    }

    // MARK: - Live metering

    /// Poll the recorder's input level (20 Hz) into a rolling buffer so the mic hero
    /// shows the learner's actual voice, mirroring the dictation waveform.
    private func startMetering() {
        let barCount = 32
        levels = Array(repeating: 0, count: barCount)
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.recording.observeAudioLevel()
            for await meter in stream {
                guard self.phase == .recording else { break }
                var next = self.levels
                next.removeFirst()
                next.append(CGFloat(min(1.0, max(0.0, meter.averagePower))))
                self.levels = next
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        levels = []
    }
}

private extension ShadowingGOP.Comparison {
    /// Mean per-phoneme GOP improvement (attempt − target), positive = closer to
    /// native. nil when there are no compared phonemes — the value persisted onto
    /// `PracticeAttempt.gopDelta`.
    var meanDelta: Double? {
        guard !phonemes.isEmpty else { return nil }
        let total = phonemes.reduce(0.0) { $0 + $1.delta }
        return total / Double(phonemes.count)
    }
}
