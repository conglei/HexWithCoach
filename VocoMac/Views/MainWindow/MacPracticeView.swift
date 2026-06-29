//
//  MacPracticeView.swift
//  VocoMac
//
//  The macOS Practice surface (MC-R6) — the drill half of the Coach hub, mirroring
//  the iOS `PracticeView` (PR-2) natively. Three sections:
//
//    1. Paste hero — "Practice your own": paste/type a script, speech, or phrase,
//       see it broken into speakable lines, and start a practice session that
//       persists a `.pasted` `PracticeItem` (PR-1 model, shared in VocoEngine).
//    2. Continue · from your coach — coach-generated drills from `CoachCardEntity`
//       rows that carry a non-empty `practiceText` and are still in the feed
//       (`statusRaw == "new"`). Each launches a practice session.
//    3. Phrasebook — saved phrasings (`statusRaw == "saved"`), each launchable too.
//
//  Coach drills + phrasebook create a `.coachInsight` / `.phrasebook` `PracticeItem`
//  on first launch (linked back via `sourceID`), so practising a coach card or a
//  saved phrase becomes a tracked, synced practice target.
//
//  The "Say it better" card action in `MacCoachView` deep-links here: it sets the
//  hub's `pendingPracticeTarget`, which switches the hub to this surface and is
//  preloaded below into a fresh paste session.
//
//  Data: `@Query` `CoachCardEntity` (VocoEngine) and `@Environment(\.modelContext)`
//  off the injected shared `ModelContainer`. Practice items / attempts are their
//  OWN synced type (`PracticeItem` / `PracticeAttempt`) — deliberately separate
//  from `TranscriptEntry`, so they NEVER surface in any History `@Query`.
//
//  No macOS shadowing engine yet (iOS `ShadowingView`/`ShadowingModel` are
//  Voco-only): the practice session presents the target lines and logs a
//  `PracticeAttempt`, advancing the never-punishing streak (`CoachStreakStore`,
//  VocoCore). When a Mac TTS/ASR shadowing drill lands, it slots into
//  `MacPracticeSessionView` without changing this surface. The streak header is
//  shared with MC-R7 (Progress) — kept to a thin read of `CoachStreakStore`.
//

import SwiftUI
import SwiftData
import VocoCore
import WidgetKit

struct MacPracticeView: View {
    /// Deep-link target from a Review card's "Say it better" (set by `MacCoachView`).
    /// When non-nil, a fresh paste session is preloaded with this phrase. Cleared
    /// once consumed so re-selecting the same card re-triggers it.
    @Binding var pendingTarget: String?

    /// Coach-generated drills: `.new` cards that carry a speakable `practiceText`.
    /// Saved ones surface under Phrasebook below so a drill never appears twice.
    @Query(
        filter: #Predicate<CoachCardEntity> {
            $0.practiceText != nil && $0.practiceText != "" && $0.statusRaw == "new"
        },
        sort: \CoachCardEntity.createdAt, order: .reverse
    )
    private var coachDrills: [CoachCardEntity]

    /// Saved phrasings — promoted out of the hidden bookmark into a real drill list.
    @Query(
        filter: #Predicate<CoachCardEntity> { $0.statusRaw == "saved" },
        sort: \CoachCardEntity.createdAt, order: .reverse
    )
    private var phrasebook: [CoachCardEntity]

    @Environment(\.modelContext) private var modelContext

    /// The session currently being practiced (drives the sheet). A `.pasted` source
    /// for the paste hero / deep-link; a `.coachInsight` / `.phrasebook` source for
    /// the drill rows.
    @State private var session: MacPracticeSession?

    init(pendingTarget: Binding<String?> = .constant(nil)) {
        _pendingTarget = pendingTarget
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MacPracticeStreakHeader()
                pasteHero
                coachSection
                phrasebookSection
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $session) { session in
            MacPracticeSessionView(session: session)
        }
        // Deep-link: a card's "Say it better" preloads its target as a paste
        // session. Consume it once so it doesn't re-fire on every redraw.
        .onChange(of: pendingTarget) { _, target in
            guard let target, !target.isEmpty else { return }
            startPasted(text: target)
            pendingTarget = nil
        }
        .onAppear {
            if let target = pendingTarget, !target.isEmpty {
                startPasted(text: target)
                pendingTarget = nil
            }
        }
    }

    // MARK: - 1. Paste hero

    private var pasteHero: some View {
        MacPasteHero { text in startPasted(text: text) }
    }

    // MARK: - 2. Continue · from your coach

    @ViewBuilder
    private var coachSection: some View {
        if !coachDrills.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Continue", subtitle: "from your coach")
                drillCard(coachDrills) { card in
                    startCoachDrill(card)
                }
            }
        }
    }

    // MARK: - 3. Phrasebook

    @ViewBuilder
    private var phrasebookSection: some View {
        if !phrasebook.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Phrasebook", subtitle: "saved phrasings")
                drillCard(phrasebook) { card in
                    startPhrasebook(card)
                }
            }
        }
    }

    @ViewBuilder
    private func drillCard(_ cards: [CoachCardEntity], onPlay: @escaping (CoachCardEntity) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                MacDrillRow(
                    title: drillTitle(for: card),
                    subtitle: lensLabel(card.lens),
                    phrase: practiceTarget(for: card),
                    onPlay: { onPlay(card) }
                )
                if index < cards.count - 1 { Divider() }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.4))
        )
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.title3.weight(.bold))
            Text("· \(subtitle)").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Session creation (PracticeItem — synced, never in History)

    /// Create + persist a `.pasted` `PracticeItem` from arbitrary text, then present
    /// the session. Used by both the paste hero and the "Say it better" deep-link.
    private func startPasted(text: String) {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = MacSentenceSegmenter.segments(from: source)
        guard !segments.isEmpty else { return }
        let item = PracticeItem(sourceText: source, segments: segments, origin: .pasted)
        modelContext.insert(item)
        try? modelContext.save()
        session = MacPracticeSession(item: item)
    }

    /// Create (or reuse) a `.coachInsight` `PracticeItem` for this card, linked back
    /// via `sourceID`, then present the session.
    private func startCoachDrill(_ card: CoachCardEntity) {
        let target = practiceTarget(for: card)
        guard !target.isEmpty else { return }
        let item = upsertItem(
            for: card.id,
            origin: .coachInsight,
            text: target,
            title: drillTitle(for: card)
        )
        session = MacPracticeSession(item: item)
    }

    /// Create (or reuse) a `.phrasebook` `PracticeItem` for this saved card.
    private func startPhrasebook(_ card: CoachCardEntity) {
        let target = practiceTarget(for: card)
        guard !target.isEmpty else { return }
        let item = upsertItem(
            for: card.id,
            origin: .phrasebook,
            text: target,
            title: drillTitle(for: card)
        )
        session = MacPracticeSession(item: item)
    }

    /// Fetch an existing `PracticeItem` for a source card (so repeated practice
    /// accumulates attempts on one item) or create one. Synced; never in History.
    private func upsertItem(
        for sourceID: UUID,
        origin: PracticeItem.Origin,
        text: String,
        title: String
    ) -> PracticeItem {
        let descriptor = FetchDescriptor<PracticeItem>(
            predicate: #Predicate { $0.sourceID == sourceID }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let item = PracticeItem(
            title: title,
            sourceText: text,
            segments: MacSentenceSegmenter.segments(from: text),
            origin: origin,
            sourceID: sourceID
        )
        modelContext.insert(item)
        try? modelContext.save()
        return item
    }

    // MARK: - Helpers (mirror iOS PracticeView)

    /// A real, speakable sentence — the practice text when present, else the
    /// displayed rewrite (older cards / non-pronunciation lenses).
    private func practiceTarget(for card: CoachCardEntity) -> String {
        if let practice = card.practiceText, !practice.isEmpty { return practice }
        return card.nativeRewrite ?? ""
    }

    /// The line shown on a drill row: the natural rewrite when there is one, else
    /// the card's title/summary.
    private func drillTitle(for card: CoachCardEntity) -> String {
        if let better = card.nativeRewrite, !better.isEmpty { return better }
        return card.title
    }

    private func lensLabel(_ lens: Lens) -> String {
        switch lens {
        case .grammar: "Grammar"
        case .lexis: "Word choice"
        case .discourse: "Clarity"
        case .pronunciation: "Pronunciation"
        case .prosody: "Fluency"
        }
    }
}

// MARK: - Streak header (shared seam with MC-R7)

/// A thin streak glance reading the never-punishing review streak from the App
/// Group (`CoachStreakStore`, VocoCore). Intentionally minimal: the full progress
/// digest (per-lens levels, GOP trends, wins) is MC-R7's `MacProgressView`. Kept as
/// its own small view so MC-R7 can lift / share it without reworking this surface.
private struct MacPracticeStreakHeader: View {
    private let streak = CoachStreakStore.load()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(streak.current > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(streakText).font(.subheadline.weight(.semibold))
                Text(streakSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.4))
        )
    }

    private var streakText: String {
        streak.current == 0 ? "Start your streak" : "\(streak.current)-day streak"
    }

    private var streakSubtitle: String {
        streak.best > streak.current
            ? "Best \(streak.best) days · keep practicing"
            : "Practice a drill to keep it going"
    }
}

// MARK: - Paste hero

/// "Practice your own": paste/type a script, see the live segment count, and start.
/// Hands the trimmed text back to the parent, which persists a `.pasted`
/// `PracticeItem` and presents the session.
private struct MacPasteHero: View {
    let onStart: (String) -> Void

    @State private var text = ""

    private var segments: [String] { MacSentenceSegmenter.segments(from: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Practice your own").font(.headline)
                    Text("Paste a script, speech, or phrase you want to say better.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste or type here…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                if !segments.isEmpty {
                    Text("\(segments.count) line\(segments.count == 1 ? "" : "s") to practice")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onStart(text)
                    text = ""
                } label: {
                    Text(segments.count <= 1 ? "Start" : "Practice \(segments.count) lines")
                }
                .buttonStyle(.borderedProminent)
                .disabled(segments.isEmpty)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.4))
        )
    }
}

// MARK: - Drill row

/// A single drill: the rule/summary + a play button that launches the session.
private struct MacDrillRow: View {
    let title: String
    let subtitle: String
    let phrase: String
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !phrase.isEmpty {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("Practice this phrase")
                .accessibilityLabel("Practice this phrase")
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(isHovering ? Color.secondary.opacity(0.06) : .clear)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Practice session

/// Identifiable wrapper so a `PracticeItem` can drive a `.sheet(item:)`.
struct MacPracticeSession: Identifiable {
    let id = UUID()
    let item: PracticeItem
}

/// The practice session sheet. Presents the target lines and, on completion, logs a
/// `PracticeAttempt` onto the (synced) `PracticeItem` and advances the streak.
///
/// There is no macOS shadowing engine yet (TTS/ASR/GOP live in the iOS
/// `ShadowingModel`); this is the native session shell. When a Mac shadowing drill
/// lands it replaces the line list here with the per-segment record/score loop and
/// writes real `perSegmentScores` — the persistence + streak wiring already in
/// place stays unchanged.
private struct MacPracticeSessionView: View {
    let session: MacPracticeSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var logged = false

    private var item: PracticeItem { session.item }
    private var segments: [String] {
        item.segments.isEmpty ? [item.sourceText] : item.segments
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, sentence in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.tint)
                                .frame(minWidth: 22, alignment: .trailing)
                            Text(sentence)
                                .font(.body)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        if index < segments.count - 1 { Divider() }
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 460)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice").font(.headline)
                Text("\(segments.count) line\(segments.count == 1 ? "" : "s") · say each one out loud")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                logAttempt()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    /// Record a `PracticeAttempt` on the item and count today toward the streak.
    /// Idempotent within a session. No `perSegmentScores` yet (no Mac scorer); the
    /// attempt marks that the learner practiced, which is what advances the streak.
    private func logAttempt() {
        guard !logged else { return }
        logged = true
        let attempt = PracticeAttempt(item: item)
        modelContext.insert(attempt)
        try? modelContext.save()

        // Never-punishing streak (RC-6 / CI-12), shared with the Review feed and
        // MC-R7's Progress digest via the App Group.
        let next = StreakCalculator.recording(CoachStreakStore.load(), reviewedOn: Date())
        CoachStreakStore.save(next)
        WidgetCenter.shared.reloadTimelines(ofKind: "HexWidgets")
    }
}

// MARK: - Sentence segmentation (macOS-local)

/// Split arbitrary pasted/typed text into speakable lines. iOS has its own
/// `SentenceSegmenter` in the `Voco` target (out of scope to touch here), so this
/// is a small macOS-local equivalent using the system tokenizer. A follow-up could
/// promote a shared segmenter into VocoCore so both platforms share one.
enum MacSentenceSegmenter {
    static func segments(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sentences: [String] = []
        trimmed.enumerateSubstrings(
            in: trimmed.startIndex..<trimmed.endIndex,
            options: [.bySentences, .localized]
        ) { substring, _, _, _ in
            let line = substring?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !line.isEmpty { sentences.append(line) }
        }
        // Fallback: enumeration can yield nothing for fragments with no terminator.
        return sentences.isEmpty ? [trimmed] : sentences
    }
}
