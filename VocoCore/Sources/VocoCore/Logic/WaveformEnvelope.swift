//
//  WaveformEnvelope.swift
//  VocoCore
//
//  Reduces raw audio samples to a small set of normalized amplitude bars for a
//  playback waveform — the real shape of a recording, not a decorative pattern.
//  Pure and cross-platform so it can be unit-tested in VocoCore; the audio file
//  decode lives in the app layer (see PhonemeRecognizer.loadSamples).
//

import Foundation

public enum WaveformEnvelope {
    /// Reduce raw audio `samples` to `count` amplitude bars, each the RMS energy
    /// of its slice, peak-normalized so the loudest bar reaches 1.0.
    ///
    /// Returns values in 0…1. When there are fewer samples than requested bars
    /// (or the clip is silent) the result is a flat zero strip — the caller draws
    /// its own visible floor, so the UI still renders a tidy bar set.
    public static func bars(from samples: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard samples.count >= count else { return Array(repeating: 0, count: count) }

        let total = samples.count
        var bars = [Float](repeating: 0, count: count)
        for i in 0 ..< count {
            // Even slices across the clip; the last bar absorbs any remainder.
            let start = i * total / count
            let end = max(start + 1, (i + 1) * total / count)
            var sumSquares: Float = 0
            for j in start ..< end {
                let s = samples[j]
                sumSquares += s * s
            }
            bars[i] = (sumSquares / Float(end - start)).squareRoot()
        }

        guard let peak = bars.max(), peak > 0 else { return bars }
        return bars.map { $0 / peak }
    }
}
