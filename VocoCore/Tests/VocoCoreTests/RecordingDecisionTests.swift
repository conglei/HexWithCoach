import Foundation
import Testing
@testable import VocoCore

/// Boundary/edge-case spec for `RecordingDecisionEngine.decide`.
///
/// The mainline cases (short press discarded, printable proceeds, long hold
/// proceeds, missing start time) already live in `RecordingDecisionTests` inside
/// HotKeyProcessorTests. This suite adds the boundary conditions that one isn't
/// exercising — written against the documented contract, not the implementation:
///   • exactly meeting `minimumKeyTime` should count as meeting it,
///   • a zero minimum should accept even an instant tap,
///   • backwards clock skew should be treated as "not long enough".
@Suite struct RecordingDecisionBoundaryTests {
    private let start = Date(timeIntervalSinceReferenceDate: 10_000)

    // `.a` is resolved contextually against `HotKey.init(key:)` (the key type is
    // Sauce's `Key` on macOS, which isn't directly nameable from the test module).
    private let modifierOnly = HotKey(key: nil, modifiers: [.option])
    private let printable = HotKey(key: .a, modifiers: [.command])

    private func decide(_ hotkey: HotKey, min: TimeInterval, elapsed: TimeInterval?) -> RecordingDecisionEngine.Decision {
        RecordingDecisionEngine.decide(
            RecordingDecisionEngine.Context(
                hotkey: hotkey,
                minimumKeyTime: min,
                recordingStartTime: elapsed == nil ? nil : start,
                currentTime: elapsed == nil ? start : start.addingTimeInterval(elapsed!)
            )
        )
    }

    @Test func modifierOnly_heldExactlyMinimum_proceeds() {
        // "Must meet minimumKeyTime" — landing exactly on the threshold meets it.
        #expect(decide(modifierOnly, min: 0.2, elapsed: 0.2) == .proceedToTranscription)
    }

    @Test func modifierOnly_instantTapWithZeroElapsed_discards() {
        // Pressed and released in the same instant (start == current, but a start
        // time exists) — distinct from "never started".
        #expect(decide(modifierOnly, min: 0.2, elapsed: 0.0) == .discardShortRecording)
    }

    @Test func modifierOnly_zeroMinimum_acceptsInstantTap() {
        // With no configured minimum, even an instant tap is acceptable.
        #expect(decide(modifierOnly, min: 0.0, elapsed: 0.0) == .proceedToTranscription)
    }

    @Test func modifierOnly_negativeElapsedFromClockSkew_discards() {
        // current before start (clock moved backwards) is not a valid long hold.
        #expect(decide(modifierOnly, min: 0.2, elapsed: -1.0) == .discardShortRecording)
    }

    @Test func printableKey_negativeElapsed_stillProceeds() {
        // A printable key proceeds regardless of (even nonsensical) timing.
        #expect(decide(printable, min: 0.2, elapsed: -1.0) == .proceedToTranscription)
    }

    @Test func printableKey_neverStarted_proceeds() {
        #expect(decide(printable, min: 0.2, elapsed: nil) == .proceedToTranscription)
    }
}
