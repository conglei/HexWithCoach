//
//  CoachWeeklySummary.swift
//  VocoCore
//
//  CF-1 — the weekly summary that opens the Coach "Focus" surface. A professional
//  coach gives a short, plain-language recap before any list. This is that recap:
//  2–4 sentences synthesizing the coaching across ALL FIVE lenses — grammar / word
//  choice / structure / clarity included, weighted for the comfortable speaker —
//  with our numbers interpolated.
//
//  Two paths, ONE shared input (`CoachSummaryInput`) so they can never contradict
//  the data:
//    1. GROUNDED LLM recap (paid / key present): the model is handed the
//       already-aggregated, already-critic-verified findings + our numbers and asked
//       only to PRIORITIZE and PHRASE — to summarize, never to generate new claims.
//       Hallucination risk lives in inventing findings; strict grounding removes it.
//       Two hard rules enforced by construction: (a) every number is computed by us
//       and lives in the prompt's data block — the LLM never does arithmetic;
//       (b) the LLM may reference only the findings it is given.
//    2. STRUCTURED TEMPLATE fallback (keyless / paid-off / LLM error): a leaner
//       recap assembled from the same objective signals + findings, so the summary
//       DEGRADES rather than DISAPPEARS.
//
//  Generated ONCE PER ROLLUP and cached by the app (not per view), to fit the
//  cost/cadence control (CE-5). The pure template generator and the input builder
//  live here so both are fast-testable in `swift test`; the grounded path is a thin
//  async layer over a `CoachLLM` that always falls back to the template.
//

import Foundation

// MARK: - Summary input (the single source both paths read)

/// The pre-aggregated, pre-verified material a weekly summary is built from. ALL
/// numbers are computed by us and frozen here, so neither path ever asks the model
/// to count or do math — it only phrases what's in this struct.
public struct CoachSummaryInput: Sendable, Equatable {
    /// Total speaking time this rollup, in seconds (sum of note durations).
    public var totalSpokenSec: Double
    /// Notes captured in the rollup window.
    public var noteCount: Int
    /// The five-lens skill map (level + trend) — the landscape the recap leans on.
    public var skillMap: [LensSkill]
    /// The ranked focus areas (the prioritized findings). `first` is the hero.
    public var focuses: [FocusArea]
    /// A freshly-mastered pattern to celebrate, when present (positive-leaning lead).
    public var leadWin: RecurringPattern?
    /// Objective fluency delta vs the prior week, when a two-week history exists:
    /// negative = fewer fillers/minute (an improvement). nil when not computable.
    public var fillersPerMinuteDelta: Double?
    /// This rollup's mean fillers/minute, when measured. nil when no pause stats.
    public var fillersPerMinute: Double?

    public init(
        totalSpokenSec: Double,
        noteCount: Int,
        skillMap: [LensSkill],
        focuses: [FocusArea],
        leadWin: RecurringPattern? = nil,
        fillersPerMinuteDelta: Double? = nil,
        fillersPerMinute: Double? = nil
    ) {
        self.totalSpokenSec = totalSpokenSec
        self.noteCount = noteCount
        self.skillMap = skillMap
        self.focuses = focuses
        self.leadWin = leadWin
        self.fillersPerMinuteDelta = fillersPerMinuteDelta
        self.fillersPerMinute = fillersPerMinute
    }

    /// Build the input from the Focus surface + the weekly rollups. Centralizes ALL
    /// the arithmetic (durations, filler delta) so the summary paths stay number-free.
    public static func make(
        surface: CoachFocusSurface,
        weekly: [CoachWeeklyRollup]
    ) -> CoachSummaryInput {
        // Latest week is the rollup window; the prior week (if any) feeds the delta.
        let sorted = weekly.sorted { $0.weekStart < $1.weekStart }
        let latest = sorted.last
        let prior = sorted.count >= 2 ? sorted[sorted.count - 2] : nil

        let delta: Double?
        if let latest, let prior {
            delta = latest.meanFillersPerMinute - prior.meanFillersPerMinute
        } else {
            delta = nil
        }

        return CoachSummaryInput(
            totalSpokenSec: latest?.totalDurationSec ?? 0,
            noteCount: latest?.noteCount ?? 0,
            skillMap: surface.skillMap,
            focuses: surface.focuses,
            leadWin: surface.leadWin,
            fillersPerMinuteDelta: delta,
            fillersPerMinute: latest?.meanFillersPerMinute
        )
    }
}

// MARK: - The summary result

/// A rendered weekly summary + which path produced it (so the UI can badge a
/// template-only recap, and tests can assert the fallback fired).
public struct CoachWeeklySummary: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case llm       // grounded LLM recap
        case template  // structured-template fallback
    }

    /// The recap prose (2–4 sentences).
    public var text: String
    public var source: Source

    public init(text: String, source: Source) {
        self.text = text
        self.source = source
    }
}

// MARK: - Template generator (pure, the fallback + the grounding spine)

/// The keyless structured-template recap. Pure + deterministic so it's testable and
/// so the grounded path has a guaranteed floor. Assembles 2–4 sentences from the
/// shared input: an opener (time spoken), the lead win when there is one, the hero
/// focus with its evidence, and a forward-looking close.
public enum CoachSummaryTemplate {

    /// Render the template recap from the shared input.
    public static func render(_ input: CoachSummaryInput) -> String {
        var sentences: [String] = []

        // 1. Opener — how much you spoke, framed as practice, not surveillance.
        if input.totalSpokenSec > 0 {
            sentences.append("This week you spoke \(durationPhrase(input.totalSpokenSec)) across \(input.noteCount) note\(input.noteCount == 1 ? "" : "s").")
        } else if input.noteCount > 0 {
            sentences.append("You captured \(input.noteCount) note\(input.noteCount == 1 ? "" : "s") this week.")
        }

        // 2. Lead with a win when there is one (positive-leaning).
        if let win = input.leadWin {
            sentences.append("Nice work — you've mastered \(lowerFirst(win.summary)).")
        }

        // 3. The hero focus: the one thing to work on, with its evidence + an
        //    example, framed as a refinement (your next 5%), never a verdict.
        if let hero = input.focuses.first {
            sentences.append(focusSentence(hero))
        }

        // 4. A measurable, growth-framed close — an objective delta when we have
        //    one, else a forward-looking nudge from the skill map.
        if let close = closingSentence(input) {
            sentences.append(close)
        }

        // Never return empty: a brand-new user still gets a warm, honest line.
        if sentences.isEmpty {
            return "Keep speaking with Voco — once you've built up a little history, your weekly recap and the one thing to polish next will show up here."
        }
        return sentences.joined(separator: " ")
    }

    /// The hero-focus sentence: lens-aware, evidence-bearing, refinement-framed.
    private static func focusSentence(_ focus: FocusArea) -> String {
        let what = lowerFirst(focus.title)
        let evidence = "(\(focus.frequency)× this week)"
        let lead: String
        switch focus.lens {
        case .lexis:
            lead = "Your biggest polish right now is word choice: \(what) \(evidence)"
        case .discourse:
            lead = "The clearest win is tightening how you structure ideas: \(what) \(evidence)"
        case .prosody:
            lead = "On delivery, \(what) \(evidence) is the habit worth smoothing"
        case .grammar:
            lead = "One recurring pattern worth a look: \(what) \(evidence)"
        case .pronunciation:
            lead = "A sound that keeps surfacing: \(what) \(evidence)"
        }
        if let span = focus.exampleSpan, !span.isEmpty {
            return "\(lead) — e.g. “\(span)”."
        }
        return "\(lead)."
    }

    /// A growth-framed closing line. Prefers a real objective delta (fillers down),
    /// else nods to the strongest lens so the recap ends on momentum.
    private static func closingSentence(_ input: CoachSummaryInput) -> String? {
        if let delta = input.fillersPerMinuteDelta, abs(delta) >= 0.3 {
            if delta < 0 {
                return "Your filler rate is down \(abs(delta).rounded(to: 1)) per minute from last week — keep it going."
            } else {
                return "Filler words ticked up \(delta.rounded(to: 1)) per minute this week; worth a little attention."
            }
        }
        // No delta — close on the lens that's furthest along (steady momentum).
        if let strongest = input.skillMap.max(by: { $0.level < $1.level }), strongest.level > 0 {
            return "\(lensDisplay(strongest.lens)) is your strongest area — you're refining from a high base."
        }
        return nil
    }

    // MARK: Number → prose helpers (the ONLY place arithmetic happens)

    static func durationPhrase(_ sec: Double) -> String {
        let minutes = Int((sec / 60).rounded())
        if minutes >= 60 {
            let hours = Double(minutes) / 60
            return "~\(hours.rounded(to: 1)) hour\(hours >= 1.95 ? "s" : "")"
        }
        if minutes >= 1 { return "~\(minutes) minute\(minutes == 1 ? "" : "s")" }
        return "a little"
    }

    static func lensDisplay(_ lens: Lens) -> String {
        switch lens {
        case .grammar: "Grammar"
        case .lexis: "Word choice"
        case .discourse: "Clarity"
        case .pronunciation: "Pronunciation"
        case .prosody: "Fluency"
        }
    }

    private static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}

// MARK: - Grounded LLM prompt builder (pure)

/// Builds the strict-grounding prompt for the LLM recap. Pure + testable: the
/// system prompt forbids new claims and arithmetic; the user prompt is a data block
/// of OUR numbers + the verified findings. The model's only job is to choose an
/// order and phrase it as an expert peer. Kept separate from the network call so a
/// test can assert the data block carries every number (no model math).
public enum CoachSummaryPrompt {

    /// The system instruction: voice + the two hard grounding rules.
    public static let system = """
    You are an expert English speaking coach writing a short weekly recap for an \
    already-fluent professional who speaks English for hours a day. This is a polish \
    tool, not a learn-English tool. Speak as a peer ("your next 5%"), never as a \
    teacher correcting a student. Frame everything as refinement, not remediation. \
    Naturalness over correctness. No condescension, no gamification, no over-explaining.

    HARD RULES — you will be given a JSON block of verified findings and numbers:
    1. Use ONLY the findings in the data block. Do NOT invent new observations, \
    examples, or claims of any kind.
    2. Do NOT do arithmetic or state any number that is not already in the data \
    block. Every count, duration, level, and delta you mention must be copied \
    verbatim from the data.
    Write 2 to 4 sentences. Lead with a win when one is given. Name the single \
    highest-priority focus and why it matters. End on measurable, growth-framed \
    momentum. Return plain prose, no markdown, no lists.
    """

    /// The user prompt: a JSON-ish data block of our pre-computed material. Built
    /// from the SAME input the template uses, so the two paths can't diverge.
    public static func userPrompt(_ input: CoachSummaryInput) -> String {
        var lines: [String] = []
        lines.append("DATA (all numbers are final — copy them, never recompute):")
        lines.append("- spoken_this_week: \(CoachSummaryTemplate.durationPhrase(input.totalSpokenSec))")
        lines.append("- notes_this_week: \(input.noteCount)")
        if let fpm = input.fillersPerMinute {
            lines.append("- fillers_per_minute: \(String(format: "%.1f", fpm))")
        }
        if let delta = input.fillersPerMinuteDelta {
            let dir = delta < 0 ? "down" : "up"
            lines.append("- fillers_per_minute_change_vs_last_week: \(dir) \(String(format: "%.1f", abs(delta)))")
        }
        if let win = input.leadWin {
            lines.append("- mastered_win: \(win.summary)")
        }
        lines.append("- skill_levels (0-100, higher is better):")
        for skill in input.skillMap {
            lines.append("    - \(CoachSummaryTemplate.lensDisplay(skill.lens)): level \(skill.level), trend \(skill.trend.rawValue)")
        }
        lines.append("- prioritized_findings (highest priority first — name the FIRST as the focus):")
        if input.focuses.isEmpty {
            lines.append("    - (none cleared the evidence bar this week)")
        } else {
            for focus in input.focuses {
                var f = "    - lens=\(CoachSummaryTemplate.lensDisplay(focus.lens)); finding=\(focus.title); times_this_week=\(focus.frequency)"
                if let span = focus.exampleSpan, !span.isEmpty { f += "; example=\"\(span)\"" }
                lines.append(f)
            }
        }
        lines.append("")
        lines.append("Write the recap now, obeying the two hard rules.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Grounded generator (thin async layer; always falls back)

/// Produces the weekly summary: tries the grounded LLM recap when an `llm` is
/// supplied, and falls back to the structured template on any error / empty
/// response / no key. The app calls this once per rollup and caches the result.
public struct CoachWeeklySummaryGenerator: Sendable {
    private let llm: CoachLLM?

    /// - Parameter llm: the provider adapter when a key is present; `nil` forces the
    ///   keyless template path.
    public init(llm: CoachLLM?) {
        self.llm = llm
    }

    /// Generate the recap. Never throws — the template is the guaranteed floor.
    public func generate(_ input: CoachSummaryInput) async -> CoachWeeklySummary {
        guard let llm else {
            return CoachWeeklySummary(text: CoachSummaryTemplate.render(input), source: .template)
        }
        do {
            // The recap is the critic-tier task (synthesis), text-only (no audio).
            let raw = try await llm.generateJSON(
                systemPrompt: CoachSummaryPrompt.system,
                userPrompt: CoachSummaryPrompt.userPrompt(input),
                audio: nil,
                tier: .critic
            )
            let text = Self.extractProse(raw)
            guard !text.isEmpty else {
                return CoachWeeklySummary(text: CoachSummaryTemplate.render(input), source: .template)
            }
            return CoachWeeklySummary(text: text, source: .llm)
        } catch {
            return CoachWeeklySummary(text: CoachSummaryTemplate.render(input), source: .template)
        }
    }

    /// The summary prompt asks for plain prose, but the `CoachLLM` seam is
    /// JSON-oriented (it requests a JSON response). Accept either: if the model
    /// returned a JSON object with a `summary`/`recap`/`text` field, pull that; else
    /// treat the whole body as prose. Trim and collapse whitespace.
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
