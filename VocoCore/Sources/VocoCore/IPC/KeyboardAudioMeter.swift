//
//  KeyboardAudioMeter.swift
//  VocoCore
//
//  A tiny shared "live mic level" channel between the host app and the keyboard
//  extension. During a Flow Session the host holds the mic (the keyboard can't),
//  so it streams the current input level (0…1) here; the keyboard polls it to draw
//  a *real* waveform instead of a synthesized one.
//
//  Unlike the JSON mailboxes this is hot-path: it's overwritten ~20×/second. So it
//  stores a fixed 12-byte little record — an 8-byte wall-clock stamp plus a 4-byte
//  Float level — and is written atomically (rename), so a reader never sees a torn
//  value. The stamp lets the reader treat a level as stale (silence) once the host
//  stops updating it, so the bars settle when capture ends or the app is suspended.
//
//  The directory is injected (like AppGroupMailbox) so it's unit-testable against a
//  temp directory without a real App Group entitlement.
//

import Foundation

public struct KeyboardAudioMeter: Sendable {
    private let fileURL: URL

    public init(directory: URL, filename: String = IPCFile.meter) {
        self.fileURL = directory.appendingPathComponent(filename)
    }

    /// Resolve the App Group container, or nil if the entitlement is missing.
    public init?(appGroupIdentifier: String) {
        guard let dir = AppGroupMailbox<DictationResult>.appGroupDirectory(appGroupIdentifier) else {
            return nil
        }
        self.init(directory: dir)
    }

    /// A read level along with how old it is, so callers can decide on staleness.
    public struct Sample: Equatable, Sendable {
        public let level: Float
        public let age: TimeInterval
    }

    /// Overwrite the latest normalized level (clamped to 0…1) with a fresh stamp.
    public func write(level: Float, at time: Date = Date()) {
        let clamped = level.isFinite ? min(max(level, 0), 1) : 0
        let stamp = time.timeIntervalSinceReferenceDate
        var bytes = Data(count: 12)
        bytes.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: stamp, toByteOffset: 0, as: Double.self)
            raw.storeBytes(of: clamped, toByteOffset: 8, as: Float.self)
        }
        try? bytes.write(to: fileURL, options: .atomic)
    }

    /// The most recent sample, or nil if nothing has been written. `age` is how
    /// long ago it was stamped — callers treat an old sample as silence.
    public func read(now: Date = Date()) -> Sample? {
        guard let data = try? Data(contentsOf: fileURL), data.count >= 12 else { return nil }
        let (stamp, level): (Double, Float) = data.withUnsafeBytes { raw in
            (raw.loadUnaligned(fromByteOffset: 0, as: Double.self),
             raw.loadUnaligned(fromByteOffset: 8, as: Float.self))
        }
        guard level.isFinite else { return Sample(level: 0, age: 0) }
        let age = now.timeIntervalSinceReferenceDate - stamp
        return Sample(level: min(max(level, 0), 1), age: age)
    }

    /// The current level if it's fresher than `maxAge`, else nil (stale → silence).
    public func currentLevel(maxAge: TimeInterval = 0.4, now: Date = Date()) -> Float? {
        guard let sample = read(now: now), sample.age <= maxAge, sample.age >= -maxAge else { return nil }
        return sample.level
    }

    /// Remove the channel (call when a session ends so the keyboard settles).
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
