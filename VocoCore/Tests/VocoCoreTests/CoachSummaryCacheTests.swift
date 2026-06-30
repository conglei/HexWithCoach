import Foundation
import Testing
@testable import VocoCore

/// CF-fix — the per-week persistent cache that stops the recap from regenerating
/// (and re-wording) on every tab visit. Freshness = same ISO week + same input hash.
struct CoachSummaryCacheTests {

    private func input(focus: String = "overuses “basically”", win: String? = nil) -> CoachRecapInput {
        CoachRecapInput(
            lensTrends: [(.lexis, .needsWork), (.grammar, .needsWork)],
            findings: [CoachRecapInput.Finding(lens: .lexis, phrase: focus, trend: .needsWork, example: "basically just")],
            leadWinPhrase: win)
    }

    private var isoCal: Calendar { CoachSummaryCacheKey.isoCalendar }

    // MARK: Key derivation

    @Test
    func sameInputSameWeekProducesSameKey() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CoachSummaryCacheKey.make(input: input(), now: now)
        let b = CoachSummaryCacheKey.make(input: input(), now: now)
        #expect(a == b)
    }

    @Test
    func changedFindingChangesTheHashSoItRegenerates() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CoachSummaryCacheKey.make(input: input(focus: "overuses “basically”"), now: now)
        let b = CoachSummaryCacheKey.make(input: input(focus: "stitches clauses"), now: now)
        #expect(a.isoWeek == b.isoWeek)        // same week
        #expect(a.inputHash != b.inputHash)    // but the input changed
        #expect(a != b)
    }

    @Test
    func weekRolloverChangesTheKeyEvenWithSameInput() {
        let week1 = Date(timeIntervalSince1970: 1_700_000_000)
        let week2 = week1.addingTimeInterval(8 * 24 * 3600)   // next ISO week
        let a = CoachSummaryCacheKey.make(input: input(), now: week1)
        let b = CoachSummaryCacheKey.make(input: input(), now: week2)
        #expect(a.isoWeek != b.isoWeek)
        #expect(a != b)
    }

    @Test
    func isoWeekLabelIsStableAndFormatted() {
        // 2026-06-29 is a Monday in ISO week 27 of 2026.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 29
        let date = isoCal.date(from: comps)!
        let label = CoachSummaryCacheKey.isoWeek(for: date, calendar: isoCal)
        #expect(label == "2026-W27")
    }

    // MARK: Store round-trip + freshness

    @Test
    func storeReusesAFreshEntryAndRejectsAStaleOne() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coach-cache-test-\(UUID().uuidString)")
            .appendingPathComponent("weekly-summary.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = CoachSummaryCacheStore(url: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let key = CoachSummaryCacheKey.make(input: input(), now: now)
        let summary = CoachWeeklySummary(text: "Refine your word choice.", source: .llm)

        // Nothing cached yet.
        #expect(store.fresh(for: key) == nil)

        try store.save(CoachSummaryCacheEntry(key: key, summary: summary, generatedAt: now))

        // Same key → reused verbatim (the stable-recap guarantee).
        let fresh = store.fresh(for: key)
        #expect(fresh?.text == "Refine your word choice.")
        #expect(fresh?.source == .llm)

        // A different week/input → not fresh, caller must regenerate.
        let staleKey = CoachSummaryCacheKey.make(input: input(focus: "different"), now: now)
        #expect(store.fresh(for: staleKey) == nil)
    }
}
