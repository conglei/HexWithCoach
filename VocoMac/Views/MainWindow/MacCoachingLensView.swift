//
//  MacCoachingLensView.swift
//  VocoMac
//
//  MC-R12: the macOS "Coaching" lens for one transcript's detail. The native
//  counterpart to the iOS `LayeredTranscriptView` + `CoachIssuesPanel`, built from
//  the SAME shared VocoCore pieces (`GOPColoring`, `PronunciationSummary`,
//  `PronunciationResult`, `WordTiming`) — the iOS views themselves are in `Voco/`
//  and are NOT imported here.
//
//  Everything in this file is READ-ONLY rendering of data already persisted with
//  the note: it never triggers analysis and never prompts a download. The heavy
//  `TranscriptAnalysis` sidecar (`entry.wordTimings` / `entry.pronunciationResult`)
//  is faulted only when the detail view renders this lens — never in the list
//  window (MC-R8 leanness is preserved).
//
//  Layout (MC-R13 — coaching is the hero, not the debug trail):
//    1. "Structure & word choice" — this note's coach cards (`CoachCardEntity`
//       filtered to `transcriptID == entry.id`): you-said (quiet) → more-natural
//       (the emphasis) → why. These lead; they are the product.
//    2. A COMPACT GOP-tinted "What you said" transcript (per-word color from
//       `GOPColoring`) as context below the cards — body size, not a display headline.
//    3. "Sounds to work on" — the `PronunciationSummary` lessons.
//
//  The old raw-GOP "What the Coach noticed" debug list (signed goodness-of-
//  pronunciation floats) is intentionally removed — meaningless/alarming to users.
//
//  When the note has no coaching yet, a friendly "Not reviewed yet" state shows.
//

import AppKit
import SwiftData
import SwiftUI
import VocoCore

/// The Coaching lens body for one transcript. Owns its own `@Query` of coach cards
/// (filtered to this note) so it composes cleanly inside the detail's ScrollView.
struct MacCoachingLensView: View {
    let entry: TranscriptEntry

    @Environment(\.modelContext) private var modelContext

    /// This note's coach cards, faulted only here. SwiftData predicates can't read
    /// a captured optional UUID cleanly, so we query the kind and filter in-memory.
    @Query private var allCards: [CoachCardEntity]

    init(entry: TranscriptEntry) {
        self.entry = entry
        let noteID = entry.id
        _allCards = Query(
            filter: #Predicate<CoachCardEntity> { $0.transcriptID == noteID },
            sort: \.createdAt
        )
    }

    /// Improvement cards (the win card is surfaced separately, see `winCard`).
    private var improvementCards: [CoachCardEntity] {
        allCards.filter { $0.kind == .improvement }.sorted { $0.createdAt < $1.createdAt }
    }

    private var winCard: CoachCardEntity? {
        allCards.first { $0.kind == .win }
    }

    /// True once *either* coaching lane has run for this note.
    private var hasBeenReviewed: Bool {
        entry.coachAnalyzedAt != nil || entry.objectiveAnalyzedAt != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !hasBeenReviewed {
                notReviewedState
            } else {
                // Coaching is the hero: the cards lead, the (now compact) transcript
                // follows as context, then the pronunciation lessons. The raw GOP
                // debug trail is intentionally gone (MC-R13).
                structureSection
                layeredTranscript
                soundsToWorkOn
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Not-reviewed state

    private var notReviewedState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not reviewed by the Coach yet", systemImage: "hourglass")
                .font(.headline)
            Text("Coaching for this note will appear here once it's been reviewed — the GOP-colored transcript, the sounds to work on, and the Coach's suggestions.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(card)
    }

    // MARK: - 1. GOP-colored layered transcript

    /// The note's words tinted by their persisted per-word GOP bucket (the warmest
    /// tint = "work on this"). Falls back to the plain transcript when no word
    /// timings exist. Read-only — never triggers analysis.
    @ViewBuilder
    private var layeredTranscript: some View {
        if let words = entry.wordTimings, !words.isEmpty {
            let decorated = MacTranscriptDecorator.decorate(
                words: words,
                pronunciation: entry.pronunciationResult,
                cards: improvementCards
            )
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("What you said")
                MacFlowLayout(spacing: 5, lineSpacing: 6) {
                    ForEach(Array(decorated.enumerated()), id: \.offset) { _, item in
                        wordChip(item)
                    }
                }
                if !legendBuckets(decorated).isEmpty || hasUnderlines(decorated) {
                    legend(decorated)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(card)
        } else {
            // No word timings: just the plain transcript, calmly — body size, it's
            // context here, not the hero (MC-R13).
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("What you said")
                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(card)
        }
    }

    private func wordChip(_ item: MacDecoratedWord) -> some View {
        Text(item.text)
            .font(.body)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                tint(for: item.bucket),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            // Meaning-span underline (grammar / word choice).
            .overlay(alignment: .bottom) {
                if item.card != nil {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: 2)
                }
            }
            .help(item.card?.title ?? "")
    }

    /// Soft GOP tint behind a word — warmer = worse. Clear and slightly-off words
    /// stay plain so the eye goes to what genuinely needs work (matches iOS:
    /// `tintSlightlyOff == false`).
    private func tint(for bucket: GOPColoring.Bucket) -> Color {
        switch bucket {
        case .weak: return Color.red.opacity(0.22)
        case .fair, .good, .neutral: return .clear
        }
    }

    private func legendBuckets(_ decorated: [MacDecoratedWord]) -> [GOPColoring.Bucket] {
        let present = Set(decorated.map(\.bucket))
        return present.contains(.weak) ? [.weak] : []
    }

    private func hasUnderlines(_ decorated: [MacDecoratedWord]) -> Bool {
        decorated.contains { $0.card != nil }
    }

    private func legend(_ decorated: [MacDecoratedWord]) -> some View {
        HStack(spacing: 14) {
            ForEach(legendBuckets(decorated), id: \.self) { _ in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.22))
                        .frame(width: 12, height: 12)
                    Text("work on")
                }
            }
            if hasUnderlines(decorated) {
                HStack(spacing: 4) {
                    Rectangle().fill(Color.accentColor).frame(width: 14, height: 2)
                    Text("word choice / grammar")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - 2. Structure & word choice (coach cards)

    @ViewBuilder
    private var structureSection: some View {
        if !improvementCards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Structure & word choice")
                ForEach(improvementCards) { card in
                    coachCardRow(card)
                }
            }
        } else if let win = winCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Structure & word choice")
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.green)
                    Text(win.title).font(.callout.weight(.medium))
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(card)
            }
        } else if entry.coachAnalyzedAt != nil {
            // Reviewed by the LLM lane but nothing flagged — a clean note.
            Label("No coaching notes for this one", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// One coach card: lens chip → you-said → a more-natural rewrite → the why.
    private func coachCardRow(_ card: CoachCardEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(lensLabel(card.lens).uppercased())
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.accentColor)

            // Quiet setup: what you originally said.
            if let span = card.originalSpan, !span.isEmpty {
                Text("You said “\(span)”")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // The emphasis: the more-natural rewrite is the takeaway — bold, primary.
            if let rewrite = card.nativeRewrite, !rewrite.isEmpty {
                Text("A more natural way: “\(rewrite)”")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text(card.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !card.detail.isEmpty {
                Text(card.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                )
        )
    }

    /// Human label for a coaching lens (mirrors the iOS lens display intent).
    private func lensLabel(_ lens: Lens) -> String {
        switch lens {
        case .grammar: return "Grammar"
        case .lexis: return "Word choice"
        case .discourse: return "Clarity"
        case .pronunciation: return "Pronunciation"
        case .prosody: return "Fluency"
        }
    }

    // MARK: - 3. Sounds to work on (PronunciationSummary)

    /// The pronunciation summary lessons — moved here under the Coaching lens
    /// (previously the only coaching shown in the Note view).
    @ViewBuilder
    private var soundsToWorkOn: some View {
        if let result = entry.pronunciationResult {
            let lessons = PronunciationSummary.lessons(from: result)
            if !lessons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Sounds to work on")
                    ForEach(lessons) { lesson in
                        lessonRow(lesson)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(card)
            }
        }
    }

    private func lessonRow(_ lesson: PronunciationLesson) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(lessonHeadline(lesson))
                    .font(.subheadline.weight(.medium))
                if !lesson.exampleWords.isEmpty {
                    Text("in " + lesson.exampleWords.map { "“\($0)”" }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func lessonHeadline(_ lesson: PronunciationLesson) -> String {
        if let actual = lesson.actual {
            return "/\(lesson.expected)/ — sounded like /\(actual)/"
        } else if let leading = lesson.leadingObserved {
            return "/\(lesson.expected)/ — unclear, more like /\(leading)/"
        } else {
            return "/\(lesson.expected)/ — unclear"
        }
    }

    // MARK: - Shared chrome

    /// Section anchor: a primary-color headline (MC-R13 — the old faint gray caps
    /// were too low-contrast to anchor sections).
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.primary)
    }

    private var card: some ShapeStyle { Color(.windowBackgroundColor).opacity(0.5) }
}

// MARK: - Pure decoration (macOS-local, reusing shared VocoCore types)

/// A display word fused with its persisted GOP score and any coach card whose
/// `originalSpan` matches a run starting at it. The macOS counterpart to the iOS
/// `DecoratedWord` — built on the same shared `WordTiming` / `WordScore` /
/// `PronunciationResult` / `GOPColoring`, kept local to VocoMac (the iOS view is
/// not importable). Pure, read-only.
struct MacDecoratedWord {
    let timing: WordTiming
    let score: WordScore?
    let card: CoachCardEntity?

    var text: String { timing.word }
    var bucket: GOPColoring.Bucket { GOPColoring.bucket(forGOP: score?.gop) }
}

/// Aligns persisted signals (GOP scores, coach-card spans) onto the display words.
/// Read-only; no analysis. The macOS counterpart to the iOS `TranscriptDecorator`.
enum MacTranscriptDecorator {
    static func decorate(
        words: [WordTiming],
        pronunciation: PronunciationResult?,
        cards: [CoachCardEntity]
    ) -> [MacDecoratedWord] {
        let scores = matchScores(words: words, pronunciation: pronunciation)
        let cardByIndex = matchCards(words: words, cards: cards)
        return words.enumerated().map { index, timing in
            MacDecoratedWord(timing: timing, score: scores[index], card: cardByIndex[index])
        }
    }

    /// Walk both streams forward, pairing scored words to display words on
    /// normalized equality (the analyzer scores only a subset, in order).
    static func matchScores(words: [WordTiming], pronunciation: PronunciationResult?) -> [WordScore?] {
        var result = [WordScore?](repeating: nil, count: words.count)
        guard let scored = pronunciation?.words, !scored.isEmpty else { return result }
        var s = 0
        for i in words.indices where s < scored.count {
            if normalize(words[i].word) == normalize(scored[s].word) {
                result[i] = scored[s]
                s += 1
            }
        }
        return result
    }

    /// Locate each card's `originalSpan` as a consecutive run of words; the first
    /// word of a matched span carries the card (the underline target).
    static func matchCards(words: [WordTiming], cards: [CoachCardEntity]) -> [Int: CoachCardEntity] {
        var out: [Int: CoachCardEntity] = [:]
        let normWords = words.map { normalize($0.word) }
        for card in cards {
            guard let span = card.originalSpan, !span.isEmpty else { continue }
            let needle = tokenize(span)
            guard !needle.isEmpty else { continue }
            if let start = firstRun(of: needle, in: normWords), out[start] == nil {
                out[start] = card
            }
        }
        return out
    }

    private static func firstRun(of needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0 ... (haystack.count - needle.count) where Array(haystack[i ..< i + needle.count]) == needle {
            return i
        }
        return nil
    }

    private static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Minimal flow layout (macOS)

/// A small wrapping layout for the word chips — the macOS-local equivalent of the
/// iOS `FlowLayout`. Lays children left-to-right, wrapping to a new line when the
/// proposed width is exceeded.
struct MacFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - spacing)
        let width = proposal.width ?? max(0, maxLineWidth)
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
