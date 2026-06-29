import Foundation
import Testing

// `KeyboardState.swift` is compiled directly into this test target (see the
// project config) — an app-extension module isn't linkable from a test bundle,
// so we test the pure state file in-module rather than `@testable import`-ing it.

@MainActor
struct KeyboardStateTests {
    @Test
    func noFullAccessTakesPrecedence() {
        let s = KeyboardState()
        s.hasFullAccess = false
        s.isCapturing = true
        #expect(s.phase == .noFullAccess)
    }

    @Test
    func capturingShowsRecording() {
        let s = KeyboardState()
        s.hasFullAccess = true
        s.isCapturing = true
        #expect(s.phase == .recording)
    }

    @Test
    func liveSessionPastExpiryNeedsBounce() {
        let s = KeyboardState()
        s.hasFullAccess = true
        s.sessionActive = true
        s.sessionExpiresAt = Date(timeIntervalSince1970: 100)
        s.clock = Date(timeIntervalSince1970: 200)
        #expect(s.phase == .needsBounce)
    }

    @Test
    func remainingTextFormatsMinutesSeconds() {
        let s = KeyboardState()
        s.sessionActive = true
        s.clock = Date(timeIntervalSince1970: 0)
        s.sessionExpiresAt = Date(timeIntervalSince1970: 95) // 1:35
        #expect(s.remainingText == "1:35")
    }
}
