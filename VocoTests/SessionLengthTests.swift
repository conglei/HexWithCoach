import Testing
@testable import HexIOS

/// Sanity coverage for the iOS app target's pure value logic. Mostly this proves
/// the HexIOSTests bundle compiles, links the HexIOS app module, and runs — the
/// foundation for testing iOS-only code (DictationModel, CoachPreferences, the
/// keyboard IPC wiring) going forward.
struct SessionLengthTests {
    @Test
    func durations() {
        #expect(SessionLength.five.duration == 300)
        #expect(SessionLength.fifteen.duration == 900)
        #expect(SessionLength.sixty.duration == 3600)
        #expect(SessionLength.never.duration == nil)
    }

    @Test
    func labels() {
        #expect(SessionLength.five.label == "5 min")
        #expect(SessionLength.fifteen.label == "15 min")
        #expect(SessionLength.never.label == "Never")
    }

    @Test
    func allCasesAreIdentifiable() {
        #expect(SessionLength.allCases.map(\.id) == [5, 15, 60, 0])
    }
}

struct TranscriptKindTests {
    @Test
    func labelsAndIcons() {
        #expect(TranscriptKind.dictation.label == "Dictation")
        #expect(TranscriptKind.note.label == "Note")
        #expect(TranscriptKind.dictation.systemImage == "keyboard")
        #expect(TranscriptKind.note.systemImage == "note.text")
    }

    @Test
    func roundTripsThroughRawValue() {
        #expect(TranscriptKind(rawValue: "dictation") == .dictation)
        #expect(TranscriptKind(rawValue: "note") == .note)
    }
}
