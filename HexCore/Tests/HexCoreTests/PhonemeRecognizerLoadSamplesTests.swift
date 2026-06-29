import AVFoundation
import Foundation
import Testing
@testable import HexCore

/// Regression for the keyboard audio-format bug: the Flow Session keyboard records
/// `.caf` in the device-native format (commonly 48 kHz stereo), but the GOP loader
/// used to require exactly 16 kHz mono and threw `unsupportedAudioFormat` otherwise —
/// which `CoachService` swallowed, so keyboard-dictated notes silently got no
/// pronunciation coaching. `loadSamples` now resamples / down-mixes any source to
/// 16 kHz mono float. These tests run on macOS via `swift test` (AVFoundation only,
/// no Core ML model needed).
struct PhonemeRecognizerLoadSamplesTests {

    /// Write `seconds` of a 220 Hz tone to a temp file in the given format.
    private func writeTone(sampleRate: Double,
                           channels: AVAudioChannelCount,
                           seconds: Double,
                           ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: channels,
                                   interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0 ..< Int(channels) {
            let p = buffer.floatChannelData![ch]
            for i in 0 ..< Int(frames) {
                p[i] = Float(sin(2.0 * Double.pi * 220.0 * Double(i) / sampleRate))
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test func readsAlready16kMono() throws {
        let url = try writeTone(sampleRate: 16_000, channels: 1, seconds: 1.0, ext: "wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let samples = try PhonemeRecognizer.loadSamples(url: url)
        // ~1 s at 16 kHz (frame count depends on the test's AVAudioFile WAV round-trip).
        #expect(abs(samples.count - 16_000) < 800)
    }

    @Test func resamplesKeyboardStyle48kStereoCaf() throws {
        // Mirrors the keyboard's SessionAudioEngine: .caf, device-native 48 kHz stereo.
        let url = try writeTone(sampleRate: 48_000, channels: 2, seconds: 1.0, ext: "caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let samples = try PhonemeRecognizer.loadSamples(url: url)
        // ~16 kHz worth of mono samples for 1 s of audio (allow resampler edge slack).
        #expect(abs(samples.count - 16_000) < 800)
    }

    @Test func resamples44kMono() throws {
        let url = try writeTone(sampleRate: 44_100, channels: 1, seconds: 0.5, ext: "wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let samples = try PhonemeRecognizer.loadSamples(url: url)
        #expect(abs(samples.count - 8_000) < 800)
    }
}
