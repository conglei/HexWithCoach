//
//  CoachWeeklySummary.swift
//  VocoCore
//
//  CF-fix — the weekly "This week" card, split into TWO independent parts so the
//  LLM can never fabricate a number or invent praise:
//
//    1. A DETERMINISTIC STATS BLOCK (`CoachStats`): minutes spoken, notes logged,
//       fillers/minute — every number computed by US, rendered as labeled metrics.
//       The LLM never produces, restates, or sees any of these numbers.
//
//    2. A QUALITATIVE LLM COACHING RECAP (2–4 sentences, NO numbers): the model is
//       handed ONLY number-free, verified findings (lens + finding phrase + an
//       example span + a grounded trend word) and asked to PRIORITIZE and PHRASE.
//       It may reference only the findings it is given, and it may not state any
//       number. On EMPTY findings it is not even called — we emit a deterministic
//       honest line ("Nothing stands out to drill right now…"), never invented
//       perfection ("flawless / level 10").
//
//  Why the split: the prior design fed the LLM our counts/levels and asked it to
//  "end on growth-framed momentum", so on the common empty-findings case it invented
//  praise. Removing every number from the model's input — and refusing to call it at
//  all when there's nothing grounded to say — removes the fabrication surface.
//
//  After the model returns, a deterministic VALIDATOR (`CoachRecapValidator`) runs
//  before anything is shown: it REJECTS (→ template fallback) any recap that leaks a
//  number, references a finding we didn't provide, or breaks length/plain-prose.
//
//  Everything here is pure + fast-testable in `swift test`. The grounded path is a
//  thin async layer over a `CoachLLM` that always falls back to the template.
//

import Foundation

// MARK: - Deterministic stats block (numbers live ONLY here, never near the LLM)

/// The honest, computed-by-us metrics for the "This week" card. Rendered as labeled
/// numbers; the LLM never sees or restates these. All arithmetic that produces a
/// user-facing number happens in `make` — nowhere else.
public struct CoachStats: Sendable, Equatable {
    /// Whole minutes spoken this week (rounded from total note duration).
    public var minutesSpoken: Int
    /// Notes logged in the rollup window.
    public var noteCount: Int
    /// This week's mean fillers/minute, when measured. nil when no pause stats.
    public var fillersPerMinute: Double?
    /// Change in fillers/minute vs the prior week (negative = improvement). nil when
    /// there's no two-week history to compare.
    public var fillersPerMinuteDelta: Double?

    public init(
        minutesSpoken: Int,
        noteCount: Int,
        fillersPerMinute: Double? = nil,
        fillersPerMinuteDelta: Double? = nil
    ) {
        self.minutesSpoken = minutesSpoken
        self.noteCount = noteCount
        self.fillersPerMinute = fillersPerMinute
        self.fillersPerMinuteDelta = fillersPerMinuteDelta
    }

    /// Build the deterministic stats from the weekly rollups. Centralizes ALL the
    /// arithmetic (duration → minutes, filler delta) so nothing downstream recomputes.
    public static func make(weekly: [CoachWeeklyRollup]) -> CoachStats {
        let sorted = weekly.sorted { $0.weekStart < $1.weekStart }
        let latest = sorted.last
        let prior = sorted.count >= 2 ? sorted[sorted.count - 2] : nil

        let delta: Double?
        if let latest, let prior {
            delta = latest.meanFillersPerMinute - prior.meanFillersPerMinute
        } else {
            delta = nil
        }

        let minutes = Int(((latest?.totalDurationSec ?? 0) / 60).rounded())
        return CoachStats(
            minutesSpoken: minutes,
            noteCount: latest?.noteCount ?? 0,
            fillersPerMinute: latest?.meanFillersPerMinute,
            fillersPerMinuteDelta: delta
        )
    }

    /// Whether there's anything to show in the stats block at all.
    public var hasData: Bool { minutesSpoken > 0 || noteCount > 0 }
}

// MARK: - Recap input (the NUMBER-FREE material the recap is built from)

/// The qualitative, NUMBER-FREE material a recap is built from. Deliberately carries
/// no counts, levels, durations, or deltas — the LLM phrases only what's here, so it
/// has nothing numeric to leak. The deterministic numbers live in `CoachStats`.
public struct CoachRecapInput: Sendable, Equatable {
    /// One verified finding the recap may reference — number-free.
    public struct Finding: Sendable, Equatable {
        public var lens: Lens
        /// The finding phrase (e.g. "overuses 'basically'") — no count.
        public var phrase: String
        /// The lens's grounded trend word.
        public var trend: CoachLensTrend
        /// A representative verbatim example span, when known.
        public var example: String?

        public init(lens: Lens, phrase: String, trend: CoachLensTrend, example: String? = nil) {
            self.lens = lens
            self.phrase = phrase
            self.trend = trend
            self.example = example
        }
    }

    /// The five-lens trend landscape (number-free), in `Lens.allCases` order.
    public var lensTrends: [(lens: Lens, trend: CoachLensTrend)]
    /// The prioritized findings, highest priority first. `first` is the hero.
    public var findings: [Finding]
    /// A freshly-mastered pattern phrase to celebrate, when present (number-free).
    public var leadWinPhrase: String?

    public init(
        lensTrends: [(lens: Lens, trend: CoachLensTrend)],
        findings: [Finding],
        leadWinPhrase: String? = nil
    ) {
        self.lensTrends = lensTrends
        self.findings = findings
        self.leadWinPhrase = leadWinPhrase
    }

    public static func == (lhs: CoachRecapInput, rhs: CoachRecapInput) -> Bool {
        lhs.findings == rhs.findings
            && lhs.leadWinPhrase == rhs.leadWinPhrase
            && lhs.lensTrends.count == rhs.lensTrends.count
            && zip(lhs.lensTrends, rhs.lensTrends).allSatisfy { $0.lens == $1.lens && $0.trend == $1.trend }
    }

    /// Whether there are no grounded findings — the case where the prior design
    /// fabricated praise. We emit a deterministic honest line instead and never call
    /// the model.
    public var isEmpty: Bool { findings.isEmpty }

    /// Build the recap input from the Focus surface — stripping every number.
    public static func make(surface: CoachFocusSurface) -> CoachRecapInput {
        let findings = surface.focuses.map { focus in
            Finding(
                lens: focus.lens,
                phrase: focus.title,
                trend: focus.trend,
                example: focus.exampleSpan?.isEmpty == false ? focus.exampleSpan : nil
            )
        }
        return CoachRecapInput(
            lensTrends: surface.skillMap.map { ($0.lens, $0.trend) },
            findings: findings,
            leadWinPhrase: surface.leadWin?.summary
        )
    }
}

// MARK: - The summary result

/// A rendered weekly recap + which path produced it (so the UI can badge a
/// template-only recap, and tests can assert the fallback fired).
public struct CoachWeeklySummary: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case llm       // grounded LLM recap that passed the validator
        case template  // deterministic template fallback (keyless / empty / rejected)
    }

    /// The recap prose (2–4 sentences). Never contains a number.
    public var text: String
    public var source: Source

    public init(text: String, source: Source) {
        self.text = text
        self.source = source
    }
}

// MARK: - Template recap (pure, the fallback + the empty-findings honest path)

/// The deterministic recap. Pure + number-free so it's testable and so the grounded
/// path has a guaranteed floor. On empty findings it returns an HONEST line, never
/// invented perfection.
public enum CoachRecapTemplate {

    /// The exact honest line shown when nothing cleared the evidence bar. A fluent
    /// user with no active pattern is a GOOD state — we say so plainly rather than
    /// inventing "flawless / level 10".
    public static let emptyLine =
        "Nothing stands out to drill right now — keep speaking and new focuses will surface as patterns build up."

    /// Render the template recap from the number-free input.
    public static func render(_ input: CoachRecapInput) -> String {
        guard !input.isEmpty else { return emptyLine }

        var sentences: [String] = []

        // 1. Lead with a win when there is one (positive-leaning).
        if let win = input.leadWinPhrase, !win.isEmpty {
            sentences.append("Nice work — you've smoothed out \(lowerFirst(win)).")
        }

        // 2. The hero focus: the one thing to refine, with an example, framed as
        //    your next 5% — never a verdict, never a count.
        if let hero = input.findings.first {
            sentences.append(focusSentence(hero))
        }

        // 3. A forward-looking close grounded in the trend landscape — no numbers.
        if let close = closingSentence(input) {
            sentences.append(close)
        }

        return sentences.isEmpty ? emptyLine : sentences.joined(separator: " ")
    }

    /// The hero-focus sentence: lens-aware, example-bearing, refinement-framed, and
    /// strictly number-free.
    private static func focusSentence(_ finding: CoachRecapInput.Finding) -> String {
        let what = lowerFirst(finding.phrase)
        let lead: String
        switch finding.lens {
        case .lexis:
            lead = "Your biggest polish right now is word choice: \(what)"
        case .discourse:
            lead = "The clearest win is tightening how you structure ideas: \(what)"
        case .prosody:
            lead = "On delivery, \(what) is the habit worth smoothing"
        case .grammar:
            lead = "One recurring pattern worth a look: \(what)"
        case .pronunciation:
            lead = "A sound that keeps surfacing: \(what)"
        }
        if let span = finding.example, !span.isEmpty {
            return "\(lead) — e.g. “\(span)”."
        }
        return "\(lead)."
    }

    /// A growth-framed close grounded in the lens trends — number-free. Prefers a
    /// lens that's improving (momentum); else nudges that the rest is steady.
    private static func closingSentence(_ input: CoachRecapInput) -> String? {
        if let improving = input.lensTrends.first(where: { $0.trend == .improving }) {
            return "\(lensDisplay(improving.lens)) is trending up — you're refining from a strong base."
        }
        return "Everything else is holding steady — small, deliberate reps will move it."
    }

    // MARK: Display helpers

    static func lensDisplay(_ lens: Lens) -> String {
        switch lens {
        case .grammar: "Grammar"
        case .lexis: "Word choice"
        case .discourse: "Clarity"
        case .pronunciation: "Pronunciation"
        case .prosody: "Fluency"
        }
    }

    static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }
}

// MARK: - Grounded LLM prompt builder (pure, NUMBER-FREE)

/// Builds the strict-grounding prompt for the recap. Pure + testable. The user
/// prompt carries ONLY number-free findings; the system prompt forbids new claims
/// AND any number whatsoever (since there are none to copy, any digit is a leak).
public enum CoachRecapPrompt {

    /// The system instruction: peer voice + the hard grounding rules.
    public static let system = """
    You are an expert English speaking coach writing a short weekly recap for an \
    already-fluent professional who speaks English for hours a day. This is a polish \
    tool, not a learn-English tool. Speak as a peer ("your next 5%"), never as a \
    teacher correcting a student. Frame everything as refinement, not remediation. \
    Naturalness over correctness. No condescension, no gamification, no over-explaining.

    HARD RULES — you are given a list of verified findings:
    1. Use ONLY the findings provided. Do NOT invent new observations, examples, \
    levels, scores, or claims of any kind.
    2. Do NOT state ANY number, count, statistic, level, rating, or duration. There \
    are no numbers in your input and there must be none in your output. Never write \
    things like "12 times", "level 8", or "3 per minute".
    3. Never claim perfection or assign a score. If there is little to say, keep it \
    brief and honest rather than inventing praise.
    Write 2 to 4 sentences of plain prose — no markdown, no lists, no headings. Lead \
    with a win when one is given, name the single highest-priority focus and why it \
    matters as a peer, and close on encouragement.
    """

    /// The user prompt: number-free findings only, so there is nothing numeric the
    /// model could echo. Built from the same input the template uses.
    public static func userPrompt(_ input: CoachRecapInput) -> String {
        var lines: [String] = []
        lines.append("VERIFIED FINDINGS (reference only these; do not invent others; state no numbers):")
        if let win = input.leadWinPhrase, !win.isEmpty {
            lines.append("- recently_smoothed: \(win)")
        }
        lines.append("- lens_trends:")
        for entry in input.lensTrends {
            lines.append("    - \(CoachRecapTemplate.lensDisplay(entry.lens)): \(entry.trend.label)")
        }
        lines.append("- prioritized_focuses (highest priority first — name the FIRST as the focus):")
        if input.findings.isEmpty {
            lines.append("    - (none cleared the evidence bar this week)")
        } else {
            for f in input.findings {
                var line = "    - lens=\(CoachRecapTemplate.lensDisplay(f.lens)); finding=\(f.phrase); trend=\(f.trend.label)"
                if let ex = f.example, !ex.isEmpty { line += "; example=\"\(ex)\"" }
                lines.append(line)
            }
        }
        lines.append("")
        lines.append("Write the recap now, obeying the hard rules. State no numbers.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Recap validator (pure, deterministic — the gate before display)

/// A deterministic validator the LLM recap must pass before it is shown. It rejects
/// fabrication that the grounding prompt asks the model to avoid but cannot enforce:
///
///   (a) ANY number / digit, "level N", "X per minute" — the recap is number-free by
///       design, so any digit or spelled-out count is a leak.
///   (b) A finding/pattern phrase, lens, or example not present in the input.
///   (c) Broken length (not 1–4 sentences) or non-plain-prose (markdown / lists).
///
/// On rejection the generator falls back to the deterministic template, so a bad
/// model response degrades the recap rather than showing a fabrication.
public enum CoachRecapValidator {

    public enum Rejection: String, Sendable, Equatable {
        case empty                 // blank after trimming
        case containsNumber        // a digit / "level N" / "N per minute" / spelled count
        case ungroundedReference   // names a lens/finding/example we didn't provide
        case badLength             // not 1…4 sentences
        case notPlainProse         // markdown, bullet, or heading markup
    }

    /// `nil` = accepted. A `Rejection` = the first rule it broke (deterministic order).
    public static func reject(_ text: String, input: CoachRecapInput) -> Rejection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        // (c-prose) Reject markdown / list / heading markup early.
        if containsMarkup(trimmed) { return .notPlainProse }

        // (a) Any digit at all is a leak (the recap is number-free).
        if trimmed.rangeOfCharacter(from: .decimalDigits) != nil { return .containsNumber }
        // Spelled-out "level <word>" / "<word> per minute" patterns, and bare number words.
        if containsSpelledNumber(trimmed) { return .containsNumber }

        // (b) Ungrounded references: any lens NAME the model used must be one whose
        //     trend or finding we actually provided; and any quoted example must be
        //     one we supplied. (We do not police every common word — only the
        //     coach-specific surface: lens display names and quoted spans.)
        if usesUngroundedLensName(trimmed, input: input) { return .ungroundedReference }
        if usesUngroundedQuote(trimmed, input: input) { return .ungroundedReference }

        // (c-length) 1…4 sentences.
        let count = sentenceCount(trimmed)
        if count < 1 || count > 4 { return .badLength }

        return nil
    }

    public static func isValid(_ text: String, input: CoachRecapInput) -> Bool {
        reject(text, input: input) == nil
    }

    // MARK: Rule helpers

    private static func containsMarkup(_ s: String) -> Bool {
        // Markdown bullets / headings / emphasis / code fences that would mean the
        // model ignored "plain prose".
        let markers = ["* ", "- ", "#", "```", "•", "1.", "2.", "<", ">"]
        if markers.contains(where: { s.contains($0) }) { return true }
        // A leading bullet on any line.
        for line in s.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("#") { return true }
        }
        return false
    }

    /// Spelled-out quantity WORDS that read as a leaked count even without a digit.
    /// Deliberately EXCLUDES "one"…"twelve": those are far too common as pronouns
    /// ("the one to polish", "one more push") to flag without a huge false-positive
    /// rate, and a fabricated count almost always uses a digit (caught by the
    /// decimal-digit rule) or one of these unambiguous quantity words.
    private static let numberWords: Set<String> = [
        "dozen", "hundred", "thousand", "twice", "thrice",
    ]

    private static func containsSpelledNumber(_ s: String) -> Bool {
        let lowered = s.lowercased()
        // A stated rating/level or a per-minute rate is always a leak: the recap is
        // number-free, so any rating/rate phrasing is fabricated structure.
        if lowered.contains("level ") || lowered.contains("per minute") {
            return true
        }
        let tokens = lowered.split { !$0.isLetter }
        for token in tokens where numberWords.contains(String(token)) {
            return true
        }
        return false
    }

    private static func usesUngroundedLensName(_ s: String, input: CoachRecapInput) -> Bool {
        // The lens display names that ARE grounded (any lens we gave a trend or
        // finding for). The skill map always carries all five, so in practice every
        // lens name is groundable — but if a future caller passes a subset, this
        // catches a model naming a lens it was never told about.
        let groundedLenses = Set(input.lensTrends.map { $0.lens } + input.findings.map { $0.lens })
        let lowered = s.lowercased()
        for lens in Lens.allCases where !groundedLenses.contains(lens) {
            let name = CoachRecapTemplate.lensDisplay(lens).lowercased()
            if lowered.contains(name) { return true }
        }
        return false
    }

    private static func usesUngroundedQuote(_ s: String, input: CoachRecapInput) -> Bool {
        // Pull every "curly"- or straight-quoted span the recap used and require each
        // to be one we supplied as an example (case-insensitive substring match).
        let provided = input.findings.compactMap { $0.example?.lowercased() }
            + input.findings.map { $0.phrase.lowercased() }
            + (input.leadWinPhrase.map { [$0.lowercased()] } ?? [])
        let quotes = quotedSpans(in: s)
        for quote in quotes {
            let q = quote.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { continue }
            let grounded = provided.contains { $0.contains(q) || q.contains($0) }
            if !grounded { return true }
        }
        return false
    }

    /// Extract spans wrapped in straight or curly double-quotes.
    private static func quotedSpans(in s: String) -> [String] {
        var spans: [String] = []
        var current = ""
        var inside = false
        for ch in s {
            if ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}" {
                if inside { spans.append(current); current = ""; inside = false }
                else { inside = true }
            } else if inside {
                current.append(ch)
            }
        }
        return spans
    }

    private static func sentenceCount(_ s: String) -> Int {
        // Count terminal punctuation runs (., !, ?) as sentence boundaries.
        var count = 0
        var lastWasTerminator = false
        for ch in s {
            if ch == "." || ch == "!" || ch == "?" {
                if !lastWasTerminator { count += 1 }
                lastWasTerminator = true
            } else if !ch.isWhitespace {
                lastWasTerminator = false
            }
        }
        // Trailing text with no terminator still counts as a sentence.
        if !lastWasTerminator, let last = s.last, !".!?".contains(last) {
            count += 1
        }
        return max(count, s.isEmpty ? 0 : 1)
    }
}

// MARK: - Grounded generator (thin async layer; validates then falls back)

/// Produces the weekly recap: on EMPTY findings returns the honest template line
/// without calling the model; otherwise tries the grounded LLM recap, runs the
/// validator, and falls back to the template on any error / empty / rejected
/// response. The app calls this once per rollup and caches the result.
public struct CoachWeeklySummaryGenerator: Sendable {
    private let llm: CoachLLM?

    public init(llm: CoachLLM?) {
        self.llm = llm
    }

    /// Generate the recap. Never throws — the template is the guaranteed floor.
    public func generate(_ input: CoachRecapInput) async -> CoachWeeklySummary {
        // Empty findings: deterministic honest line, NEVER an LLM call (the prior
        // design's fabrication point).
        guard !input.isEmpty else {
            return CoachWeeklySummary(text: CoachRecapTemplate.render(input), source: .template)
        }
        guard let llm else {
            return CoachWeeklySummary(text: CoachRecapTemplate.render(input), source: .template)
        }
        do {
            let raw = try await llm.generateJSON(
                systemPrompt: CoachRecapPrompt.system,
                userPrompt: CoachRecapPrompt.userPrompt(input),
                audio: nil,
                tier: .critic
            )
            let text = Self.extractProse(raw)
            // The validator is the gate: a leaked number / ungrounded reference /
            // bad shape → fall back to the deterministic template.
            guard !text.isEmpty, CoachRecapValidator.isValid(text, input: input) else {
                return CoachWeeklySummary(text: CoachRecapTemplate.render(input), source: .template)
            }
            return CoachWeeklySummary(text: text, source: .llm)
        } catch {
            return CoachWeeklySummary(text: CoachRecapTemplate.render(input), source: .template)
        }
    }

    /// The `CoachLLM` seam is JSON-oriented. Accept either: a JSON object with a
    /// `summary`/`recap`/`text` field, else the whole body as prose. Trim.
    static func extractProse(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["summary", "recap", "text", "recapText"] {
                if let s = obj[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return trimmed
    }
}
