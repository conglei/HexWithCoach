//
//  CoachSummaryCache.swift
//  VocoCore
//
//  CF-fix — the per-week persistent cache for the weekly recap. The prior design
//  cached the recap only in-memory on the view-model, so every tab appearance
//  re-ran `reload()` → another (non-deterministic) LLM call → the wording changed
//  on every glance. This makes the recap STABLE within a week:
//
//    Key = ISO year-week (e.g. "2026-W26") + a stable hash of the recap INPUT.
//
//  The recap is regenerated ONLY when (a) the week rolls over or (b) the grounded
//  input changes (new findings / a new lead win). A normal glance with unchanged
//  inputs in the same week reuses the persisted recap with NO LLM call.
//
//  Persisted as JSON via `CoachPaths` so it sits beside `profile.json` /
//  `snapshots.json` in the one Coach directory. Pure key derivation + a small
//  file-backed store, both fast-testable in `swift test`.
//

import Foundation

// MARK: - Cache key (pure, deterministic)

/// The composite key that decides whether a cached recap is still fresh. Equality is
/// the freshness test: same week AND same input hash → reuse.
public struct CoachSummaryCacheKey: Codable, Sendable, Equatable {
    /// ISO 8601 year-week, e.g. "2026-W26". Rolls the cache over each week.
    public var isoWeek: String
    /// A stable hash of the number-free recap input. Changes when the findings /
    /// trends / lead win change, forcing a regenerate even within the same week.
    public var inputHash: String

    public init(isoWeek: String, inputHash: String) {
        self.isoWeek = isoWeek
        self.inputHash = inputHash
    }

    /// Derive the key for `input` as of `now`. `calendar` decides the ISO week;
    /// pass a fixed-timezone calendar for deterministic tests.
    public static func make(
        input: CoachRecapInput,
        now: Date,
        calendar: Calendar = isoCalendar
    ) -> CoachSummaryCacheKey {
        CoachSummaryCacheKey(isoWeek: isoWeek(for: now, calendar: calendar),
                             inputHash: hash(input))
    }

    /// A calendar fixed to the ISO-8601 week definition (Monday-start, week-of-year),
    /// so the week label is stable regardless of locale first-weekday quirks.
    public static let isoCalendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()

    /// "YYYY-Www" for the date's ISO week (zero-padded week number).
    public static func isoWeek(for date: Date, calendar: Calendar = isoCalendar) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 0
        let week = comps.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    /// A stable, order-independent hash of the recap input's meaningful content.
    /// Uses a simple FNV-1a over a canonical string so it's deterministic across
    /// runs/processes (Swift's `Hashable` is randomized per launch and unusable here).
    public static func hash(_ input: CoachRecapInput) -> String {
        var parts: [String] = []
        if let win = input.leadWinPhrase { parts.append("win:\(win)") }
        for entry in input.lensTrends.sorted(by: { $0.lens.rawValue < $1.lens.rawValue }) {
            parts.append("trend:\(entry.lens.rawValue)=\(entry.trend.rawValue)")
        }
        // Findings are already priority-ordered and that order is meaningful, so keep it.
        for (i, f) in input.findings.enumerated() {
            parts.append("focus\(i):\(f.lens.rawValue)|\(f.phrase)|\(f.trend.rawValue)|\(f.example ?? "")")
        }
        return fnv1a(parts.joined(separator: "\n"))
    }

    private static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

// MARK: - Cached payload

/// The persisted recap + the key it was generated for. The store hands this back so
/// a caller can decide freshness by comparing keys.
public struct CoachSummaryCacheEntry: Codable, Sendable, Equatable {
    public var key: CoachSummaryCacheKey
    public var summaryText: String
    public var sourceRaw: String
    public var generatedAt: Date

    public init(key: CoachSummaryCacheKey, summary: CoachWeeklySummary, generatedAt: Date) {
        self.key = key
        self.summaryText = summary.text
        self.sourceRaw = summary.source.rawValue
        self.generatedAt = generatedAt
    }

    public var summary: CoachWeeklySummary {
        CoachWeeklySummary(text: summaryText,
                           source: CoachWeeklySummary.Source(rawValue: sourceRaw) ?? .template)
    }
}

// MARK: - File-backed store

/// A tiny JSON store for the single cached weekly recap. Holds exactly one entry —
/// the most recent week's recap — since older weeks are never re-shown on this card.
public struct CoachSummaryCacheStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The cached entry, or nil when none is stored / the file is unreadable.
    public func load() -> CoachSummaryCacheEntry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CoachSummaryCacheEntry.self, from: data)
    }

    /// Persist the entry, creating the Coach directory if needed.
    public func save(_ entry: CoachSummaryCacheEntry) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        try data.write(to: url, options: .atomic)
    }

    /// Return the cached summary IFF it matches `key` (same week + same input);
    /// otherwise nil, meaning the caller must regenerate.
    public func fresh(for key: CoachSummaryCacheKey) -> CoachWeeklySummary? {
        guard let entry = load(), entry.key == key else { return nil }
        return entry.summary
    }
}
