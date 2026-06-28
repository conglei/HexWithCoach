import Foundation

// MARK: - Pipeline input

/// One dictation fed to the pipeline. `audio` enables the multimodal lens; word
/// timings (when the ASR provides them) sharpen the fluency signals.
public struct CoachTranscriptInput: Sendable {
    public var id: UUID
    public var text: String
    public var durationSec: Double
    public var audio: CoachAudio?
    public var wordTimings: [WordTiming]?

    public init(
        id: UUID,
        text: String,
        durationSec: Double,
        audio: CoachAudio? = nil,
        wordTimings: [WordTiming]? = nil
    ) {
        self.id = id
        self.text = text
        self.durationSec = durationSec
        self.audio = audio
        self.wordTimings = wordTimings
    }
}

// MARK: - LLM JSON contracts

/// Tier-1 extraction response — per-lens candidate observations.
struct ExtractionResponse: Codable {
    var candidates: [ExtractionCandidate]
}

public struct ExtractionCandidate: Codable, Sendable, Equatable {
    public var lens: Lens
    public var key: String          // canonical, stable across runs (dedupe in the profile)
    public var summary: String      // short label ("drops articles")
    public var span: String         // the user's exact words being flagged
    public var rule: String         // the teachable rule
    public var nativeRewrite: String
    public var severity: Int        // 1...5
    public var needsAudio: Bool
    public var context: String      // the verbatim sentence the span came from
    public var practiceText: String // a natural full sentence to say aloud (plain words, no phonetics)

    public init(
        lens: Lens, key: String, summary: String, span: String,
        rule: String, nativeRewrite: String, severity: Int, needsAudio: Bool = false,
        context: String = "", practiceText: String = ""
    ) {
        self.lens = lens
        self.key = key
        self.summary = summary
        self.span = span
        self.rule = rule
        self.nativeRewrite = nativeRewrite
        self.severity = severity
        self.needsAudio = needsAudio
        self.context = context
        self.practiceText = practiceText
    }

    enum CodingKeys: String, CodingKey {
        case lens, key, summary, span, rule, nativeRewrite, severity, needsAudio, context, practiceText
    }

    // Tolerant decode so sparse/older LLM JSON (missing the newer fields) still
    // decodes instead of throwing. Encoding stays synthesized via CodingKeys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lens = try c.decode(Lens.self, forKey: .lens)
        key = try c.decode(String.self, forKey: .key)
        summary = try c.decode(String.self, forKey: .summary)
        span = try c.decode(String.self, forKey: .span)
        rule = try c.decode(String.self, forKey: .rule)
        nativeRewrite = try c.decode(String.self, forKey: .nativeRewrite)
        severity = try c.decode(Int.self, forKey: .severity)
        needsAudio = try c.decodeIfPresent(Bool.self, forKey: .needsAudio) ?? false
        context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        practiceText = try c.decodeIfPresent(String.self, forKey: .practiceText) ?? ""
    }
}

/// Tier-2 critic response — a verdict per candidate, matched back by `index`.
struct CriticResponse: Codable {
    var verdicts: [CriticVerdict]
}

struct CriticVerdict: Codable {
    var index: Int
    var isRealError: Bool
    var rewriteIsBetter: Bool
    var confidence: Double   // 0...1
}

// MARK: - Pipeline output

/// A verified, card-ready coaching moment (deep-design §5): the user's real words
/// → a more native rewrite → the rule → which lens. RC-2/RC-3 render these.
public struct CoachInsight: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var transcriptID: UUID
    public var lens: Lens
    public var key: String
    public var summary: String
    public var rule: String
    public var originalSpan: String
    public var nativeRewrite: String
    public var severity: Int
    public var context: String      // the verbatim sentence the span came from
    public var practiceText: String // a natural full sentence to say aloud (plain words, no phonetics)

    public init(
        id: UUID = UUID(), transcriptID: UUID, lens: Lens, key: String,
        summary: String, rule: String, originalSpan: String,
        nativeRewrite: String, severity: Int,
        context: String = "", practiceText: String = ""
    ) {
        self.id = id
        self.transcriptID = transcriptID
        self.lens = lens
        self.key = key
        self.summary = summary
        self.rule = rule
        self.originalSpan = originalSpan
        self.nativeRewrite = nativeRewrite
        self.severity = severity
        self.context = context
        self.practiceText = practiceText
    }
}

/// The 1–2 highest-leverage patterns to work on now — a coach focuses.
public struct CoachFocus: Codable, Sendable, Equatable {
    public var lens: Lens
    public var patternKey: String
    public var reason: String

    public init(lens: Lens, patternKey: String, reason: String) {
        self.lens = lens
        self.patternKey = patternKey
        self.reason = reason
    }
}

/// The result of analyzing one dictation: verified insights, prioritized focuses,
/// and the local fluency signals. The caller has already had its `LearnerProfile`
/// updated in place.
public struct CoachAnalysis: Sendable, Equatable {
    public var insights: [CoachInsight]
    public var focuses: [CoachFocus]
    public var signals: FluencySignals

    public init(insights: [CoachInsight], focuses: [CoachFocus], signals: FluencySignals) {
        self.insights = insights
        self.focuses = focuses
        self.signals = signals
    }
}

// MARK: - Pipeline

/// The corpus-stateful, two-tier pipeline (deep-design §3, pillar B): extract
/// candidate observations across the five lenses, verify each with a critic pass
/// (killing false positives a competent user would reject), integrate survivors
/// into the `LearnerProfile`, and prioritize a focus.
public struct CoachPipeline: Sendable {
    public let llm: CoachLLM
    /// Critic verdicts below this confidence are dropped.
    public var confidenceThreshold: Double
    /// How many focuses to surface.
    public var maxFocuses: Int

    public init(llm: CoachLLM, confidenceThreshold: Double = 0.6, maxFocuses: Int = 2) {
        self.llm = llm
        self.confidenceThreshold = confidenceThreshold
        self.maxFocuses = maxFocuses
    }

    /// Analyze one dictation, mutating `profile` with verified observations.
    public func analyze(
        _ input: CoachTranscriptInput,
        profile: inout LearnerProfile,
        at date: Date
    ) async throws -> CoachAnalysis {
        let signals = FluencyAnalyzer.analyze(
            transcript: input.text, durationSec: input.durationSec, wordTimings: input.wordTimings
        )

        // Tier 1 — extract candidates (conditioned on the profile + objective signals).
        let extractRaw = try await llm.generateJSON(
            systemPrompt: Self.extractSystemPrompt,
            userPrompt: Self.extractUserPrompt(input: input, profile: profile, signals: signals),
            audio: input.audio,
            tier: .extract
        )
        let candidates = (try? Self.decodeJSON(ExtractionResponse.self, from: extractRaw))?.candidates ?? []
        HexLog.coach.info("Coach extract: hasAudio=\(input.audio != nil, privacy: .public) candidates=\(candidates.count, privacy: .public)")
        guard !candidates.isEmpty else {
            return CoachAnalysis(insights: [], focuses: [], signals: signals)
        }

        // Tier 2 — critic verifies each candidate; drop the low-confidence/false ones.
        // It only needs the audio when a verdict actually depends on hearing the
        // utterance (pronunciation/prosody). Text-only candidates verify cheaply.
        let criticNeedsAudio = candidates.contains { $0.needsAudio }
        let criticRaw = try await llm.generateJSON(
            systemPrompt: Self.criticSystemPrompt,
            userPrompt: Self.criticUserPrompt(input: input, candidates: candidates),
            audio: criticNeedsAudio ? input.audio : nil,
            tier: .critic
        )
        let verdicts = (try? Self.decodeJSON(CriticResponse.self, from: criticRaw))?.verdicts ?? []
        let verdictByIndex = Dictionary(verdicts.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })

        var insights: [CoachInsight] = []
        var observations: [VerifiedObservation] = []
        for (index, candidate) in candidates.enumerated() {
            guard let verdict = verdictByIndex[index],
                  verdict.isRealError, verdict.rewriteIsBetter,
                  verdict.confidence >= confidenceThreshold
            else { continue }

            insights.append(CoachInsight(
                transcriptID: input.id, lens: candidate.lens, key: candidate.key,
                summary: candidate.summary, rule: candidate.rule,
                originalSpan: candidate.span, nativeRewrite: candidate.nativeRewrite,
                severity: candidate.severity,
                context: candidate.context, practiceText: candidate.practiceText
            ))
            observations.append(VerifiedObservation(
                lens: candidate.lens, key: candidate.key, summary: candidate.summary,
                rule: candidate.rule, severity: candidate.severity,
                example: ExampleRef(transcriptID: input.id, span: candidate.span)
            ))
        }

        HexLog.coach.info("Coach critic: candidates=\(candidates.count, privacy: .public) survived=\(insights.count, privacy: .public)")
        profile.integrate(observations, at: date)
        let focuses = Self.prioritize(profile: profile, insights: insights, max: maxFocuses)
        return CoachAnalysis(insights: insights, focuses: focuses, signals: signals)
    }

    // MARK: Prioritization

    /// Rank the patterns touched this run by leverage (frequency × severity),
    /// skipping mastered ones, and take the top `max`. A coach focuses.
    static func prioritize(profile: LearnerProfile, insights: [CoachInsight], max: Int) -> [CoachFocus] {
        let touched = Set(insights.map { $0.key })
        let severityByKey = Dictionary(insights.map { ($0.key, $0.severity) }, uniquingKeysWith: Swift.max)
        let ranked = profile.patterns
            .filter { $0.status != .mastered && touched.contains($0.key) }
            .sorted { lhs, rhs in
                let l = lhs.frequency * (severityByKey[lhs.key] ?? 1)
                let r = rhs.frequency * (severityByKey[rhs.key] ?? 1)
                if l != r { return l > r }
                return lhs.frequency > rhs.frequency
            }
        return ranked.prefix(max).map {
            CoachFocus(
                lens: $0.lens, patternKey: $0.key,
                reason: $0.frequency >= 2
                    ? "Recurs \($0.frequency)× — worth focusing here."
                    : "New this batch — worth watching."
            )
        }
    }

    // MARK: Tolerant JSON decoding

    /// Decode a model response that may be wrapped in markdown fences or have
    /// leading/trailing prose. Pulls the first balanced `{…}` then decodes.
    static func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let json = extractJSONObject(from: text) ?? text
        guard let data = json.data(using: .utf8) else {
            throw CoachPipelineError.invalidJSON
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// First balanced top-level `{…}` substring (fence/prose tolerant).
    static func extractJSONObject(from text: String) -> String? {
        guard let open = text.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escape = false
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if escape { escape = false }
            else if c == "\\", inString { escape = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[open ... i]) }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}

public enum CoachPipelineError: Error, Equatable {
    case invalidJSON
}

// MARK: - Prompts

extension CoachPipeline {
    static let lensList = "grammar (grammar & usage), lexis (word choice & naturalness), discourse (conciseness & clarity), pronunciation, prosody (pace, pauses, fillers)"

    static let extractSystemPrompt = """
    You are an expert English coach analyzing the real speech of a confident
    non-native speaker (often a software engineer). Your job is naturalness and
    polish, NOT basic grammar drilling. Find the genuinely learnable moments.

    You are given an automatic transcript, and SOMETIMES the audio too — the
    prompt tells you which. The transcript comes from a different speech model and
    may be wrong; crucially it HIDES pronunciation mistakes, because it prints the
    word the speaker meant, not the sounds they made.
    - When audio is provided: trust it for what was actually said — especially for
      pronunciation and prosody — and use the transcript only to anchor word
      spans. When the audio and transcript disagree, the audio wins; quote the
      span as you actually heard it.
    - When no audio is provided: analyze the transcript as the best available
      evidence. Still flag grammar, lexis, and discourse issues. Do NOT raise
      pronunciation or prosody issues you cannot verify from text alone.

    Analyze across these lenses: \(lensList).

    Rules:
    - Flag only real, worthwhile issues. A competent speaker instantly rejects a
      wrong or pedantic correction — better to return fewer, high-value candidates.
    - For each candidate give: the exact `span` from the transcript, a short
      `summary`, the teachable `rule`, a meaning-preserving `nativeRewrite` (how a
      confident native would say it, same tone), `severity` 1–5 (impact on
      intelligibility/naturalness), `needsAudio` true for pronunciation/prosody,
      `context` (the full sentence VERBATIM from the transcript that the span came
      from — surrounding words for the learner), and `practiceText` (a complete,
      natural sentence the learner can SAY ALOUD to practice — plain words only, no
      phonetic respelling/IPA/CAPS; for grammar/lexis/discourse this is the
      corrected sentence in context, for pronunciation/prosody it is a natural
      sentence that contains the target word(s)).
    - `key` must be a stable, canonical slug for the issue TYPE (e.g.
      "drop-articles-abstract-nouns", "overuse-very", "filler-like"), so the same
      habit dedupes across sessions. Reuse the learner's existing pattern keys when
      the issue matches one.
    - Respect the learner profile: prioritize their recurring patterns and L1
      interference; don't re-flag mastered patterns.

    Pronunciation & prosody candidates (needsAudio=true) must be SPECIFIC and
    grounded in what you actually hear — vague notes like "work on your accent"
    are useless. For each:
    - span: the exact word or short phrase where you hear the issue.
    - summary: name the precise problem — the segment, syllable, or pattern, e.g.
      "'th' in 'think' said as 's'", "stress on wrong syllable: com-FOR-table",
      "short 'i' in 'ship' sounds like 'sheep'", "final cluster dropped in 'asked'",
      "flat intonation on the question".
    - nativeRewrite: the TARGET as a phonetic respelling a learner can READ —
      stress syllable in CAPS, with optional IPA in brackets, e.g.
      "THINK [θɪŋk]", "com-fort-uh-bul → COMF-tuh-bul". This is a READING cue, not
      something a text-to-speech voice should ever read out.
    - practiceText: a natural, full sentence containing the target word(s) that a
      text-to-speech voice can SPEAK and the learner can shadow — plain words only,
      NEVER the phonetic respelling, no CAPS, no IPA, e.g. "I think we should leave
      now." or "This chair is really comfortable."
    - rule: one concrete fix — articulator placement or a stress/rhythm cue, e.g.
      "put your tongue tip between your teeth for /θ/, not behind them",
      "stress the first syllable and reduce the others to 'uh'".
    Flag a sound/stress issue ONLY if you can actually hear it in the audio; never
    infer it from spelling. Prefer the 2–3 most impactful habits over many tiny ones.

    Respond with ONLY a JSON object, no prose, no code fences:
    {"candidates":[{"lens":"...","key":"...","summary":"...","span":"...","rule":"...","nativeRewrite":"...","severity":3,"needsAudio":false,"context":"...","practiceText":"..."}]}
    If there is nothing worth flagging, return {"candidates":[]}.
    """

    static let criticSystemPrompt = """
    You are a verification critic for an English coach. Keep the candidates that a
    competent non-native speaker would accept as genuine, useful corrections; drop
    the pedantic or wrong ones.

    You may be given the AUDIO of the utterance and an automatic transcript that
    can be wrong. For pronunciation/prosody candidates, judge from the audio, not
    the transcript; if you were given no audio, treat such candidates as
    unverifiable and reject them. Judge grammar/lexis/discourse candidates on the
    transcript as usual.

    For each candidate decide, independently and skeptically:
    - isRealError: is this genuinely non-native / worth correcting (not pedantic,
      not already correct)? For pronunciation/prosody, read this as "I can
      actually hear this mispronunciation or pattern in the audio."
    - rewriteIsBetter: is the proposed rewrite meaning-preserving AND genuinely
      more natural than the original? For pronunciation/prosody, read this as
      "the target respelling and the fix are accurate."
    - confidence: 0–1.
    Default to rejecting when unsure — false positives destroy trust.

    Respond with ONLY a JSON object, no prose, no code fences:
    {"verdicts":[{"index":0,"isRealError":true,"rewriteIsBetter":true,"confidence":0.9}]}
    Echo the candidate `index` exactly as given.
    """

    static func extractUserPrompt(input: CoachTranscriptInput, profile: LearnerProfile, signals: FluencySignals) -> String {
        """
        AUDIO: \(input.audio == nil ? "none for this utterance — analyze the transcript only" : "attached (authoritative — trust it over the transcript)")

        LEARNER PROFILE
        \(profileSummary(profile))

        OBJECTIVE FLUENCY SIGNALS (computed locally)
        \(signalsSummary(signals))

        REFERENCE TRANSCRIPT (from a different ASR model; may be wrong)
        \(input.text)
        """
    }

    static func criticUserPrompt(input: CoachTranscriptInput, candidates: [ExtractionCandidate]) -> String {
        let list = candidates.enumerated().map { index, c in
            "[\(index)] lens=\(c.lens.rawValue) span=\"\(c.span)\" rewrite=\"\(c.nativeRewrite)\" rule=\"\(c.rule)\""
        }.joined(separator: "\n")
        return """
        AUDIO: \(input.audio == nil ? "none — reject pronunciation/prosody candidates you cannot verify from text" : "attached (authoritative for pronunciation/prosody)")

        REFERENCE TRANSCRIPT (from a different ASR model; may be wrong)
        \(input.text)

        CANDIDATES
        \(list)
        """
    }

    static func profileSummary(_ profile: LearnerProfile) -> String {
        var lines: [String] = []
        lines.append("L1: \(profile.inferredL1 ?? "unknown")")
        if !profile.levels.isEmpty {
            let levels = Lens.allCases
                .compactMap { lens in profile.levels[lens].map { "\(lens.rawValue) \($0)" } }
                .joined(separator: ", ")
            if !levels.isEmpty { lines.append("Levels: \(levels)") }
        }
        let active = profile.patterns
            .filter { $0.status != .mastered }
            .sorted { $0.frequency > $1.frequency }
            .prefix(8)
        if active.isEmpty {
            lines.append("Recurring patterns: none yet.")
        } else {
            lines.append("Recurring patterns (reuse these keys when matching):")
            for p in active {
                lines.append("- [\(p.lens.rawValue)] key=\(p.key) \"\(p.summary)\" ×\(p.frequency) (\(p.status.rawValue))")
            }
        }
        if !profile.interferencePatterns.isEmpty {
            lines.append("L1 interference: \(profile.interferencePatterns.joined(separator: "; "))")
        }
        return lines.joined(separator: "\n")
    }

    static func signalsSummary(_ s: FluencySignals) -> String {
        var parts = [
            "words/min: \(Int(s.wordsPerMinute.rounded()))",
            "fillers/min: \(String(format: "%.1f", s.fillersPerMinute)) (\(s.fillerCount) total)",
            "restarts: \(s.restartCount)",
        ]
        if s.hasPauseStats {
            parts.append("pauses: \(s.pauseCount), long-pause rate: \(String(format: "%.2f", s.longPauseRate))")
        }
        return parts.joined(separator: ", ")
    }
}
