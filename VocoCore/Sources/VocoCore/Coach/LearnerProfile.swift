import Foundation

// MARK: - Lenses

/// The five coaching lenses (deep-design §3). A learner has a level and a set of
/// recurring patterns per lens.
public enum Lens: String, Codable, Sendable, CaseIterable, Hashable {
    case grammar        // grammar & usage
    case lexis          // lexis & naturalness (word choice, collocations)
    case discourse      // discourse, conciseness, clarity
    case pronunciation  // segmental pronunciation
    case prosody        // prosody & fluency (pace, pauses, fillers)
}

// MARK: - Pattern status

/// Lifecycle of a recurring pattern. Derived deterministically from how long it's
/// been since the pattern last recurred (see `LearnerProfile.recomputeStatuses`),
/// so the profile is stable and auditable rather than drifting run-to-run.
public enum PatternStatus: String, Codable, Sendable {
    case active     // recurring now
    case improving  // hasn't recurred for a while
    case mastered   // gone long enough to count as a win
}

// MARK: - Example reference

/// A real example of a pattern, pointing back into the user's own corpus.
public struct ExampleRef: Codable, Sendable, Equatable, Hashable {
    public var transcriptID: UUID
    /// The offending phrase, verbatim from the user's speech.
    public var span: String

    public init(transcriptID: UUID, span: String) {
        self.transcriptID = transcriptID
        self.span = span
    }
}

// MARK: - Recurring pattern (the heart of the profile)

public struct RecurringPattern: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var lens: Lens
    /// Canonical dedupe key (e.g. "drop-articles-abstract-nouns"). Supplied by the
    /// pipeline so repeated occurrences merge into one pattern.
    public var key: String
    public var summary: String   // "drops articles before abstract nouns"
    public var rule: String      // the teachable rule
    public var frequency: Int    // how often it has recurred
    public var firstSeen: Date
    public var recency: Date      // last occurrence
    public var status: PatternStatus
    public var examples: [ExampleRef]

    public init(
        id: UUID = UUID(),
        lens: Lens,
        key: String,
        summary: String,
        rule: String,
        frequency: Int = 1,
        firstSeen: Date,
        recency: Date,
        status: PatternStatus = .active,
        examples: [ExampleRef] = []
    ) {
        self.id = id
        self.lens = lens
        self.key = key
        self.summary = summary
        self.rule = rule
        self.frequency = frequency
        self.firstSeen = firstSeen
        self.recency = recency
        self.status = status
        self.examples = examples
    }
}

// MARK: - Lexical profile

public struct LexicalProfile: Codable, Sendable, Equatable {
    public var overusedWords: [String]
    public var collocationGaps: [String]
    public var rangeNote: String?

    public init(overusedWords: [String] = [], collocationGaps: [String] = [], rangeNote: String? = nil) {
        self.overusedWords = overusedWords
        self.collocationGaps = collocationGaps
        self.rangeNote = rangeNote
    }
}

// MARK: - Learner profile

/// The persistent, evolving per-user model — pillar A, the moat. Conditioned on by
/// every analysis and updated by it. Pure value type so the update logic is
/// deterministic and unit-testable.
public struct LearnerProfile: Codable, Sendable, Equatable {
    public var inferredL1: String?
    public var interferencePatterns: [String]
    public var levels: [Lens: Int]          // 1–100 per lens, growth-framed (only-up)
    public var patterns: [RecurringPattern]
    public var lexicalProfile: LexicalProfile
    public var registerTendencies: [String]
    public var goals: [String]
    public var updatedAt: Date

    public init(
        inferredL1: String? = nil,
        interferencePatterns: [String] = [],
        levels: [Lens: Int] = [:],
        patterns: [RecurringPattern] = [],
        lexicalProfile: LexicalProfile = LexicalProfile(),
        registerTendencies: [String] = [],
        goals: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.inferredL1 = inferredL1
        self.interferencePatterns = interferencePatterns
        self.levels = levels
        self.patterns = patterns
        self.lexicalProfile = lexicalProfile
        self.registerTendencies = registerTendencies
        self.goals = goals
        self.updatedAt = updatedAt
    }

    public func level(for lens: Lens) -> Int { levels[lens] ?? 0 }
}

// MARK: - Pipeline hand-off

/// A verified observation surviving CE-3's extract→critic pass, ready to merge.
public struct VerifiedObservation: Codable, Sendable, Equatable {
    public var lens: Lens
    public var key: String       // canonical dedupe key — must be stable across runs
    public var summary: String
    public var rule: String
    public var severity: Int     // 1...5, impact
    public var example: ExampleRef
    public var inferredL1: String?

    public init(
        lens: Lens,
        key: String,
        summary: String,
        rule: String,
        severity: Int = 3,
        example: ExampleRef,
        inferredL1: String? = nil
    ) {
        self.lens = lens
        self.key = key
        self.summary = summary
        self.rule = rule
        self.severity = severity
        self.example = example
        self.inferredL1 = inferredL1
    }
}

// MARK: - Update policy

/// Thresholds + scoring for profile updates. All time-based status transitions are
/// pure functions of `recency`, so the profile can be recomputed identically from
/// the same inputs (auditable; no drift).
public struct ProfileUpdatePolicy: Sendable {
    public var improvingAfter: TimeInterval
    public var masteredAfter: TimeInterval
    public var maxExamplesPerPattern: Int
    public var baseLevel: Int
    public var improvingLevelPoints: Int
    public var masteredLevelPoints: Int

    public init(
        improvingAfter: TimeInterval = 7 * 24 * 3600,
        masteredAfter: TimeInterval = 30 * 24 * 3600,
        maxExamplesPerPattern: Int = 5,
        baseLevel: Int = 10,
        improvingLevelPoints: Int = 3,
        masteredLevelPoints: Int = 8
    ) {
        self.improvingAfter = improvingAfter
        self.masteredAfter = masteredAfter
        self.maxExamplesPerPattern = maxExamplesPerPattern
        self.baseLevel = baseLevel
        self.improvingLevelPoints = improvingLevelPoints
        self.masteredLevelPoints = masteredLevelPoints
    }

    public static let `default` = ProfileUpdatePolicy()
}

// MARK: - Update logic

public extension LearnerProfile {
    /// Merge verified observations from the pipeline (CE-3). A recurrence of an
    /// existing `(lens, key)` raises `frequency`, refreshes `recency`, regresses
    /// status to `.active`, and appends the new example (deduped + capped). New
    /// keys become fresh `.active` patterns. Then statuses and levels recompute.
    mutating func integrate(
        _ observations: [VerifiedObservation],
        at date: Date,
        policy: ProfileUpdatePolicy = .default
    ) {
        for obs in observations {
            if let idx = patterns.firstIndex(where: { $0.lens == obs.lens && $0.key == obs.key }) {
                patterns[idx].frequency += 1
                patterns[idx].recency = date
                patterns[idx].status = .active
                patterns[idx].summary = obs.summary
                patterns[idx].rule = obs.rule
                if !patterns[idx].examples.contains(obs.example) {
                    patterns[idx].examples.append(obs.example)
                    let overflow = patterns[idx].examples.count - policy.maxExamplesPerPattern
                    if overflow > 0 { patterns[idx].examples.removeFirst(overflow) }
                }
            } else {
                patterns.append(RecurringPattern(
                    lens: obs.lens, key: obs.key, summary: obs.summary, rule: obs.rule,
                    frequency: 1, firstSeen: date, recency: date, status: .active,
                    examples: [obs.example]
                ))
            }
            if let l1 = obs.inferredL1, inferredL1 == nil { inferredL1 = l1 }
        }
        recomputeStatuses(asOf: date, policy: policy)
    }

    /// Derive each pattern's status from how long since it last recurred, then
    /// recompute per-lens levels. Levels only ever increase (growth-framed): a
    /// regression (the pattern recurs) refreshes recency and drops the *target*,
    /// but the stored level holds at its high-water mark.
    mutating func recomputeStatuses(asOf date: Date, policy: ProfileUpdatePolicy = .default) {
        for idx in patterns.indices {
            let age = date.timeIntervalSince(patterns[idx].recency)
            if age >= policy.masteredAfter {
                patterns[idx].status = .mastered
            } else if age >= policy.improvingAfter {
                patterns[idx].status = .improving
            } else {
                patterns[idx].status = .active
            }
        }
        for lens in Lens.allCases {
            let forLens = patterns.filter { $0.lens == lens }
            let mastered = forLens.filter { $0.status == .mastered }.count
            let improving = forLens.filter { $0.status == .improving }.count
            let target = policy.baseLevel
                + mastered * policy.masteredLevelPoints
                + improving * policy.improvingLevelPoints
            let clamped = min(100, max(1, target))
            levels[lens] = max(levels[lens] ?? policy.baseLevel, clamped)
        }
        updatedAt = date
    }
}

// MARK: - Persistence (file-JSON; syncable later via the P4-2 path)

/// Loads/saves a `LearnerProfile` as JSON at a caller-supplied URL (the iOS app
/// points this at its App Group container). ISO-8601 dates keep the file stable
/// and diffable.
public struct LearnerProfileStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Returns the stored profile, or a fresh empty one if none exists / is unreadable.
    public func load() -> LearnerProfile {
        guard let data = try? Data(contentsOf: url),
              let profile = try? Self.decoder.decode(LearnerProfile.self, from: data)
        else { return LearnerProfile(updatedAt: Date(timeIntervalSince1970: 0)) }
        return profile
    }

    public func save(_ profile: LearnerProfile) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }
}
