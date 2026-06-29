import XCTest
@testable import VocoCore

final class KeyboardAudioMeterTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meter-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRoundTripsLevelWhenFresh() throws {
        let meter = KeyboardAudioMeter(directory: tempDir())
        let t = Date()
        meter.write(level: 0.42, at: t)
        XCTAssertEqual(try XCTUnwrap(meter.currentLevel(now: t)), 0.42, accuracy: 1e-6)
    }

    func testClampsOutOfRangeLevels() throws {
        let meter = KeyboardAudioMeter(directory: tempDir())
        let t = Date()
        meter.write(level: 1.8, at: t)
        XCTAssertEqual(try XCTUnwrap(meter.currentLevel(now: t)), 1.0, accuracy: 1e-6)
        meter.write(level: -0.5, at: t)
        XCTAssertEqual(try XCTUnwrap(meter.currentLevel(now: t)), 0.0, accuracy: 1e-6)
    }

    func testStaleLevelReadsAsNil() {
        let meter = KeyboardAudioMeter(directory: tempDir())
        let t = Date()
        meter.write(level: 0.9, at: t)
        // A read half a second later is older than the default 0.4s window.
        XCTAssertNil(meter.currentLevel(maxAge: 0.4, now: t.addingTimeInterval(0.5)))
        // But still readable as a raw sample with its age.
        let sample = meter.read(now: t.addingTimeInterval(0.5))
        XCTAssertEqual(sample?.level ?? -1, 0.9, accuracy: 1e-6)
        XCTAssertEqual(sample?.age ?? 0, 0.5, accuracy: 0.05)
    }

    func testMissingChannelReadsAsNil() {
        let meter = KeyboardAudioMeter(directory: tempDir())
        XCTAssertNil(meter.read())
        XCTAssertNil(meter.currentLevel())
    }

    func testClearRemovesChannel() {
        let meter = KeyboardAudioMeter(directory: tempDir())
        meter.write(level: 0.5)
        meter.clear()
        XCTAssertNil(meter.read())
    }
}
