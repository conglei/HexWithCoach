//
//  MacCoachView.swift
//  VocoMac
//
//  The macOS Coach hub (MC-R5) — the companion window's learning surface. Mirrors
//  the iOS Coach tab (IA-1: Voco/Views/CoachView.swift) natively: a Review feed of
//  "say it better" coaching cards curated from your real speech, plus Practice
//  (MC-R6) and Progress (MC-R7) sub-sections composed as placeholders so those
//  tasks can fill them in parallel.
//
//  Keyless-first (CI-5 / ADR-0002, via `ReviewFeedGating`): the objective lane
//  (pronunciation + fluency) authors real cards with zero LLM, so the feed shows
//  whether or not a BYOK key is present. A key is never a gate — it's a
//  non-blocking upsell (`MacKeyUpsellBanner`) that unlocks the meaning lenses and
//  richer LLM teaching. Activation (IA-2): pre-activation we bait the upsell with
//  the user's real capture count ("You've captured N things this week — see how to
//  say them better"), phrased for the opt-in / paid entry.
//
//  Data: `@Query` `CoachCardEntity` (VocoEngine) newest-first off the injected
//  shared `ModelContainer`; cards are curated severity-first by `CoachCardCurator`,
//  so the newest run leads with the highest-leverage moments. Triggering ("Review
//  now" / re-analysis) and opt-in / key state come from the shared `MacCoachService`
//  / `MacCoachPreferences` (MC-R4) owned by `MacTranscriptStore.shared` — read the
//  same way `CoachV2SettingsView` does, not through TCA.
//
//  Native, not touch: hover affordances on cards/buttons, a sidebar-friendly
//  segmented control, and a flexible multi-column card grid on wide windows.
//

import AVFoundation
import SwiftUI
import SwiftData
import VocoCore

struct MacCoachView: View {
    /// Reads the shared Coach driver off `MacTranscriptStore.shared` (MC-R4), the
    /// same way `CoachV2SettingsView` does. Until the store is bootstrapped (e.g.
    /// unit tests), the services are nil and we show a quiet unavailable state.
    var body: some View {
        if let coach = MacTranscriptStore.shared.coach,
           let preferences = MacTranscriptStore.shared.coachPreferences {
            MacCoachHub(coach: coach, preferences: preferences)
        } else {
            ContentUnavailableView(
                "Coach",
                systemImage: "graduationcap",
                description: Text("Your coaching feed appears here once Voco is running.")
            )
        }
    }
}

/// Which half of the Coach hub is showing. Feedback (the Review feed) is the
/// default so the hub opens onto coaching cards, mirroring iOS.
private enum MacCoachSurface: String, CaseIterable, Identifiable {
    case feedback = "Feedback"
    case practice = "Practice"
    case progress = "Progress"
    var id: Self { self }
}

private struct MacCoachHub: View {
    @Bindable var coach: MacCoachService
    @Bindable var preferences: MacCoachPreferences

    @State private var surface: MacCoachSurface = .feedback

    /// Deep-link target for "Say it better" (MC-R6): a Review card sets this and we
    /// switch to the Practice surface, which preloads it into a fresh session.
    /// Lives here (the hub owns `surface`) so the card action can both navigate and
    /// hand off the target.
    @State private var pendingPracticeTarget: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Coach surface", selection: $surface) {
                ForEach(MacCoachSurface.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch surface {
                case .feedback:
                    MacReviewFeed(
                        coach: coach,
                        preferences: preferences,
                        onSayItBetter: { target in
                            pendingPracticeTarget = target
                            surface = .practice
                        }
                    )
                case .practice:
                    // "Say it better" on a card deep-links here with a preloaded
                    // target (MC-R6).
                    MacPracticeView(pendingTarget: $pendingPracticeTarget)
                case .progress:
                    // Placeholder (MC-R7).
                    MacProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            // Manual "Review now" override (CI-7): the LLM lane auto-runs, but a
            // keyed user with a backlog can force a run on demand. Always-on
            // objective analysis runs at capture regardless.
            ToolbarItem(placement: .primaryAction) {
                if coach.isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Reviewing…").foregroundStyle(.secondary)
                    }
                } else if showsManualReview {
                    Button { Task { await coach.analyzeBacklog() } } label: {
                        Label("Review now", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    /// Whether to offer the manual "Review now" override (CI-7). Pure gate over the
    /// shared `CoachAutomation` rule, matching iOS `ReviewView.showsManualReview`.
    private var showsManualReview: Bool {
        CoachAutomation.showsManualOverride(
            CoachAutomation.LLMInputs(
                isReady: preferences.isReady,
                autoEnabled: preferences.autoLLM,
                isIdle: !coach.isAnalyzing,
                hasBacklog: coach.backlogCount() > 0,
                underBudget: coach.budget.canAnalyze(spentThisMonth: coach.spentThisMonthUSD)
            )
        )
    }
}

// MARK: - Review feed

/// The macOS Review feed — the hero of the Coach hub. Mirrors iOS `ReviewView`:
/// keyless-first gating, a banner while a run is in progress, a non-blocking key
/// upsell (baited with the real capture count pre-activation), and a grid of
/// coaching cards. Reads cards via `@Query` off the injected shared container.
private struct MacReviewFeed: View {
    @Bindable var coach: MacCoachService
    @Bindable var preferences: MacCoachPreferences

    /// Deep-link out to Practice when a card's "Say it better" is tapped (MC-R6).
    /// The hub owns the surface + the pending target; the feed just forwards it.
    var onSayItBetter: (String) -> Void

    // Newest-first. Cards within a run are curated severity-first by
    // `CoachCardCurator`, so the most recent run leads with the highest-leverage
    // ("sounds to work on") moments — structural parity with #81–#87.
    @Query(sort: \CoachCardEntity.createdAt, order: .reverse) private var allCards: [CoachCardEntity]
    @Query(sort: \TranscriptEntry.date, order: .reverse) private var transcripts: [TranscriptEntry]

    @State private var howItWorks = false

    /// Only `.new` cards are reviewable; acted-on cards leave the feed.
    private var cards: [CoachCardEntity] { allCards.filter { $0.status == .new } }

    private var gatingInputs: ReviewFeedGating.Inputs {
        ReviewFeedGating.Inputs(
            hasCards: !cards.isEmpty,
            hasKey: preferences.isReady,
            hasNotes: !transcripts.isEmpty
        )
    }

    private var showsUpsell: Bool { ReviewFeedGating.showsKeyUpsell(gatingInputs) }

    /// Notes captured in the last 7 days — baits the pre-activation upsell with the
    /// user's real corpus (IA-2). A presentation detail (only shown while the upsell
    /// does, i.e. pre-activation), so it's computed here, not in gating.
    private var capturedThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return transcripts.filter { $0.date >= weekAgo }.count
    }

    private var backlogCount: Int { coach.backlogCount() }

    var body: some View {
        Group {
            switch ReviewFeedGating.feedState(gatingInputs) {
            case .feed:
                feed
            case .caughtUp:
                caughtUp
            case .onboarding:
                onboarding
            }
        }
        .safeAreaInset(edge: .top) {
            if coach.isAnalyzing { reviewingBanner }
        }
        .animation(.easeInOut(duration: 0.2), value: coach.isAnalyzing)
        .sheet(isPresented: $howItWorks) { howItWorksSheet }
    }

    // MARK: Feed

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsUpsell {
                    MacKeyUpsellBanner(capturedThisWeek: capturedThisWeek)
                }

                Text("TODAY")
                    .font(.caption.weight(.semibold)).tracking(1)
                    .foregroundStyle(.secondary)

                // Multi-column where it helps (native): cards flow into as many
                // ~360pt columns as the window is wide.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 16, alignment: .top)],
                          alignment: .leading, spacing: 16) {
                    ForEach(cards) { card in
                        MacCoachCardView(
                            card: card,
                            transcript: transcript(for: card),
                            onSayItBetter: onSayItBetter
                        )
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transcript(for card: CoachCardEntity) -> TranscriptEntry? {
        guard let id = card.transcriptID else { return nil }
        return transcripts.first { $0.id == id }
    }

    // MARK: States

    private var caughtUp: some View {
        ScrollView {
            VStack(spacing: 20) {
                if showsUpsell {
                    MacKeyUpsellBanner(capturedThisWeek: capturedThisWeek)
                }
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.circle")
                } description: {
                    Text(backlogCount > 0
                         ? "\(backlogCount) new dictation\(backlogCount == 1 ? "" : "s") to review."
                         : "New coaching appears here as you dictate.")
                } actions: {
                    if coach.isAnalyzing {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reviewing…") }
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    /// First-run state: nothing dictated yet. NOT a "connect a key" wall — coaching
    /// is free and on-device; you just need to speak first (mirrors iOS).
    private var onboarding: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                    .frame(width: 72, height: 72)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 6) {
                    Text("Your coaching starts here").font(.title3.weight(.semibold))
                    Text("Dictate with Voco and your pronunciation and fluency get coached automatically — free, on-device. Your cards show up here.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                Button("How coaching works") { howItWorks = true }

                if showsUpsell {
                    MacKeyUpsellBanner(capturedThisWeek: capturedThisWeek)
                        .frame(maxWidth: 460)
                }

                Label("Pronunciation & fluency analyzed on-device · the cloud is opt-in", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    /// A clear, pinned indicator while a review run is in progress — visible in
    /// every state, more informative than a bare toolbar spinner.
    private var reviewingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Reviewing your new dictations…").font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(12)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var howItWorksSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How coaching works").font(.title2.weight(.semibold))
            Text("Voco listens to the English you already speak all day — across your apps — and turns the most learnable moments into a few real, natural-sounding upgrades.")
            Text("Pronunciation and fluency coaching run entirely on this device, for free. Add your own AI key in Settings to also unlock grammar, word-choice, clarity, and intonation feedback — the cloud is always opt-in, and you can stop anytime.")
            Text("Each card shows what you said, a more natural way to say it, and why. Use “Say it better” to practice it out loud.")
            HStack {
                Spacer()
                Button("Done") { howItWorks = false }.keyboardShortcut(.defaultAction)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - Key upsell (activation, IA-2)

/// Non-blocking BYOK upsell. Pre-activation it's baited with the user's real
/// capture count ("You've captured N things this week…"), phrased for the opt-in /
/// paid entry rather than only BYOK. Never gates the keyless feed.
private struct MacKeyUpsellBanner: View {
    let capturedThisWeek: Int

    private var headline: String {
        capturedThisWeek > 0
            ? "You've captured \(capturedThisWeek) thing\(capturedThisWeek == 1 ? "" : "s") this week — see how to say them better."
            : "See how to say your English better."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.subheadline.weight(.semibold))
                Text("Turn on the English Coach in Settings to unlock grammar, word-choice, clarity, and intonation coaching. Pronunciation and fluency are already on, free and on-device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Open Settings → Coach to enable")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.tint.opacity(0.20))
        )
    }
}

// MARK: - Card

/// A single coaching card: context / you-said → a more-natural rewrite → why →
/// lens, with native actions (Got it, Not useful, Save, Say it better, play audio,
/// see-in-context). Mirrors iOS `CoachCardView`. Calm tone + selective coloring
/// (#81–#87): only the rewrite/win is tinted; everything else stays neutral.
private struct MacCoachCardView: View {
    let card: CoachCardEntity
    let transcript: TranscriptEntry?
    /// Deep-link to the Practice surface with this card's practice target (MC-R6).
    var onSayItBetter: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            cardBody
            recurrence
            Divider()
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(isHovering ? 0.9 : 0.4))
        )
        .onHover { isHovering = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
            Spacer()
            lensBadge
        }
    }

    private var sourceLabel: String {
        let kind = transcript?.kind.label ?? "Dictation"
        let time = (transcript?.date ?? card.createdAt).formatted(date: .omitted, time: .shortened)
        return "\(kind) · \(time)"
    }

    @ViewBuilder
    private var lensBadge: some View {
        if card.kind == .win {
            Label("Nice phrasing", systemImage: "checkmark")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.green.opacity(0.12), in: .capsule)
        } else {
            Text(lensLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.tint.opacity(0.12), in: .capsule)
        }
    }

    // MARK: Body

    @ViewBuilder
    private var cardBody: some View {
        if card.kind == .win {
            Text("“\(card.originalSpan ?? card.title)”").font(.body)
            if !card.detail.isEmpty {
                Text(card.detail).font(.callout).foregroundStyle(.secondary)
            }
        } else {
            if !(card.originalSpan ?? "").isEmpty || !(card.context ?? "").isEmpty {
                Text(contextAttributed).font(.body)
            }
            if let better = card.nativeRewrite {
                HStack(spacing: 4) {
                    Image(systemName: rewriteIsPhonetic ? "waveform" : "arrow.down")
                    // "SAY IT LIKE" for phonetic targets — surfaces "what an unclear
                    // sound came out as" framing (#81–#87) as a sound cue, not a reword.
                    Text(rewriteIsPhonetic ? "SAY IT LIKE" : "MORE NATURAL").tracking(0.5)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                Text("“\(better)”").font(.body.weight(.medium))
            }
            if !card.detail.isEmpty {
                Text(card.detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// The flagged span shown inside its surrounding sentence, with the user's exact
    /// words emphasized so the quote reads in context (calm, selective coloring).
    private var contextAttributed: AttributedString {
        let span = card.originalSpan ?? ""
        let context = card.context ?? ""
        if context.isEmpty {
            var plain = AttributedString("“\(span)”")
            plain.foregroundColor = .primary
            return plain
        }
        var attributed = AttributedString("“\(context)”")
        attributed.foregroundColor = .secondary
        if !span.isEmpty, let range = attributed.range(of: span, options: .caseInsensitive) {
            attributed[range].foregroundColor = .primary
            attributed[range].font = .body.weight(.semibold)
        }
        return attributed
    }

    @ViewBuilder
    private var recurrence: some View {
        if let note = card.recurrenceNote, !note.isEmpty {
            Label(note, systemImage: "repeat")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            // "Say it better" → deep-link into the Practice surface (MC-R6) with
            // this card's practice target preloaded into a fresh session.
            if card.kind == .improvement, !practiceTarget.isEmpty {
                Button { sayItBetter() } label: {
                    Label("Say it better", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Play the source audio inline when it's on disk.
            if hasAudio {
                iconButton("speaker.wave.2", help: "Play audio") { playAudio() }
            }

            Spacer()

            if card.kind == .improvement {
                iconButton("bookmark", help: "Save") { setStatus(.saved) }
            }
            iconButton("hand.thumbsdown", help: "Not useful") { setStatus(.dismissed) }
            iconButton("checkmark", help: "Got it") { setStatus(.done) }
        }
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }

    private func setStatus(_ status: CoachCardStatus) {
        card.status = status
        try? modelContext.save()
    }

    // MARK: Deep-link (MC-R6)

    /// "Say it better": hand the card's practice target up to the hub, which switches
    /// to the Practice surface and preloads it into a fresh session.
    private func sayItBetter() {
        onSayItBetter(practiceTarget)
    }

    // MARK: Audio

    private var hasAudio: Bool {
        guard let transcript else { return false }
        return MacCoachService.audioURL(for: transcript) != nil
    }

    private func playAudio() {
        guard let transcript, let url = MacCoachService.audioURL(for: transcript) else { return }
        MacCoachAudioPlayer.shared.play(url: url)
    }

    // MARK: Practice target

    /// A real, speakable sentence for shadowing — the practice text when present,
    /// else the displayed rewrite (older cards / non-pronunciation lenses).
    private var practiceTarget: String {
        if let practice = card.practiceText, !practice.isEmpty { return practice }
        return card.nativeRewrite ?? ""
    }

    // MARK: Labels

    private var lensLabel: String {
        switch card.lens {
        case .grammar: "Grammar"
        case .lexis: "Word choice"
        case .discourse: "Clarity"
        case .pronunciation: "Pronunciation"
        case .prosody: "Fluency"
        }
    }

    /// Pronunciation/prosody rewrites are a phonetic target ("THINK [θɪŋk]"), not a
    /// reworded sentence — label them so the learner reads them as a sound cue.
    private var rewriteIsPhonetic: Bool {
        card.lens == .pronunciation || card.lens == .prosody
    }
}

// MARK: - Audio playback

/// Minimal shared audio player for card "play audio" — keeps one `AVAudioPlayer`
/// alive across taps so a clip isn't deallocated mid-playback. macOS-local.
@MainActor
private final class MacCoachAudioPlayer {
    static let shared = MacCoachAudioPlayer()
    private var player: AVAudioPlayer?

    func play(url: URL) {
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }
}
