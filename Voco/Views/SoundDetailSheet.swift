//
//  SoundDetailSheet.swift
//  Voco
//
//  Tapping a row in the note's "Sounds to work on" card opens this sheet: the one
//  sound, what it came out as, the learner's own example words from the note, and —
//  when the bundled phoneme guide covers it — how to actually make the sound
//  (description + mouth-level how-to + a minimal pair + the L1 substitutions people
//  commonly fall into). A prominent "Practice this sound" launches shadowing on a
//  real practice sentence, which closes into the shadowing breakdown (Feature B).
//
//  The expected→actual + GOP-color row (`SoundLessonRow`) is factored here so the
//  note card, this sheet, and the shadowing result all read the same way.
//

import VocoCore
import SwiftUI

// MARK: - Shared expected → actual row

/// One "sound to work on" as `/expected/ → you said /actual/` with a red GOP tint
/// and the learner's own example words. Shared by the note's summary card, the
/// `SoundDetailSheet` header, and the shadowing "Your pronunciation" breakdown so
/// the same sound reads identically everywhere. Pass `showCount: false` where the
/// per-note instance count isn't meaningful (e.g. a single shadow attempt).
struct SoundLessonRow: View {
    let lesson: PronunciationLesson
    var showCount: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 6) {
                Text("/\(lesson.expected)/")
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.red)
                if let actual = lesson.actual {
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text("/\(actual)/")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.actual != nil ? "you said /\(lesson.actual!)/ instead" : "came out unclear")
                    .font(.subheadline.weight(.medium))
                if !lesson.exampleWords.isEmpty {
                    Text("in " + lesson.exampleWords.map { "“\($0)”" }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showCount {
                Text("\(lesson.count)×").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sound detail sheet

/// The tap target behind a "Sounds to work on" row: a focused page for one sound
/// with how-to-articulate teaching and a "Practice this sound" shadowing launch.
struct SoundDetailSheet: View {
    let lesson: PronunciationLesson
    @Environment(\.dismiss) private var dismiss
    @State private var showShadow = false

    /// The bundled teaching entry for this sound, when the guide covers it.
    private var guide: PhonemeGuideEntry? {
        TeachingContent.default.phonemeGuide.entry(for: lesson.expected)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    exampleWordsSection
                    if let guide { guideSection(guide) }
                    practiceButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sound to work on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .fullScreenCover(isPresented: $showShadow) {
            ShadowingView(target: practiceTarget) {}
        }
    }

    // MARK: Header — expected → actual, large

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORK ON THIS SOUND")
                .font(.caption.weight(.bold)).tracking(1)
                .foregroundStyle(.red)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ipa(lesson.expected, label: "expected", color: .red)
                if let actual = lesson.actual {
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    ipa(actual, label: "you said", color: .secondary)
                }
            }
            Text(lesson.actual != nil
                 ? "Aim for /\(lesson.expected)/ — it came out closer to /\(lesson.actual!)/."
                 : "The /\(lesson.expected)/ sound came out unclear.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous))
    }

    private func ipa(_ symbol: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("/\(symbol)/")
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
        }
    }

    // MARK: Learner's own words from the note

    @ViewBuilder private var exampleWordsSection: some View {
        if !lesson.exampleWords.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("FROM YOUR NOTE")
                    .font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                Text(lesson.exampleWords.map { "“\($0)”" }.joined(separator: ", "))
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .hexCard()
        }
    }

    // MARK: How to make the sound (bundled phoneme guide)

    @ViewBuilder private func guideSection(_ g: PhonemeGuideEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW TO SAY IT")
                .font(.caption.weight(.bold)).tracking(1)
                .foregroundStyle(HexTheme.gradientColors[1])

            Text(g.description).font(.callout)

            tip(icon: "mouth", title: "Mouth", body: g.howToArticulate)
            tip(icon: "arrow.left.arrow.right", title: "Minimal pair", body: g.minimalPair, mono: true)

            if !g.commonL1Substitutions.isEmpty {
                tip(
                    icon: "exclamationmark.triangle",
                    title: "Often swapped for",
                    body: g.commonL1Substitutions.map { "/\($0)/" }.joined(separator: ", "),
                    mono: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .hexCard()
    }

    private func tip(icon: String, title: String, body: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(HexTheme.gradientColors[1])
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(body).font(mono ? .callout.monospaced() : .callout)
            }
        }
    }

    // MARK: Practice

    private var practiceButton: some View {
        Button { showShadow = true } label: {
            Label("Practice this sound", systemImage: "waveform")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(HexGradientButtonStyle())
        .padding(.top, 4)
    }

    /// The phrase to shadow: the guide's loaded practice sentence when available,
    /// else a short sentence built from the learner's example words, else the
    /// minimal pair, else the guide's example word — always something speakable.
    private var practiceTarget: String {
        if let g = guide, !g.practiceSentence.isEmpty { return g.practiceSentence }
        if !lesson.exampleWords.isEmpty {
            return "Say it clearly: " + lesson.exampleWords.joined(separator: ", ") + "."
        }
        if let g = guide {
            if !g.minimalPair.isEmpty { return g.minimalPair }
            return g.exampleWord
        }
        return "/\(lesson.expected)/"
    }
}
