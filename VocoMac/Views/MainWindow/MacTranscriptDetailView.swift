//
//  MacTranscriptDetailView.swift
//  VocoMac
//
//  MC-R8: the History detail surface for one `TranscriptEntry`. This is the ONE
//  place that faults the heavy `TranscriptAnalysis` sidecar (word timings /
//  pronunciation) — the list/window path stays lean and never touches `analysis`.
//
//  Mirrors the iOS `TranscriptDetailView` intent natively on macOS: the full
//  transcript, an audio playback control (reusing the macOS `AudioPlayerController`
//  from `HistoryFeature`), copy, and a cascade delete (HS-3 fan-out via
//  `MacTranscriptDeletion`). The pronunciation summary is rendered from the on-row
//  signals where available; the heavy per-word timing/pronunciation result is read
//  only here, on open.
//

import AppKit
import SwiftData
import SwiftUI
import VocoCore

struct MacTranscriptDetailView: View {
    /// The selected lean row. We deliberately keep this a value passed in by the
    /// list; the sidecar is faulted lazily inside this view (see `analysisSummary`).
    let entry: TranscriptEntry
    /// Called after a successful delete so the parent can clear its selection.
    var onDelete: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    /// One audio controller per detail view; reuses the macOS playback path
    /// (`AudioPlayerController` lives in `HistoryFeature`, same module).
    @State private var audioController: AudioPlayerController?
    @State private var isPlaying = false
    @State private var showCopied = false
    @State private var confirmingDelete = false

    /// Resolve the recording the same way the capture path stores it.
    private var audioURL: URL? {
        guard let filename = entry.audioFilename, !filename.isEmpty else { return nil }
        return MacTranscriptStore.recordingsURL(for: filename)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Text(entry.text)
                    .font(.title3.weight(.medium))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if audioURL != nil { playbackBar }

                // The coaching layer is faulted only here, on open. Reading the
                // sidecar / on-row signals never happens in the list window.
                analysisSummary
            }
            .padding(20)
        }
        .navigationTitle("Transcript")
        .toolbar { toolbarButtons }
        .confirmationDialog(
            "Delete this transcript?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its audio and any coaching cards, observations, and progress for it are removed too. This can't be undone.")
        }
        .onDisappear { stopPlayback() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                copyText()
            } label: {
                Label(showCopied ? "Copied" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
            }
            .help("Copy transcript to clipboard")
        }
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete this transcript")
        }
    }

    // MARK: - Header

    /// "DICTATION · App · date" — source + timestamp line.
    private var header: some View {
        HStack(spacing: 8) {
            if let bundleID = entry.sourceAppBundleID,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: entry.kind.systemImage)
            }
            Text(entry.kind.label.uppercased())
            if let app = entry.sourceAppName { Text("· \(app)") }
            Spacer()
            Text(entry.date, format: .dateTime.month().day().hour().minute())
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    // MARK: - Playback

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPlaying ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(isPlaying ? "Playing…" : "Play audio")
                    .font(.subheadline)
                Text(String(format: "%.1fs", entry.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Coaching summary (faults the sidecar)

    /// Render the pronunciation themes for this note. Faulting the heavy result is
    /// confined to this view: `entry.pronunciationResult` reaches into the sidecar,
    /// and `entry.wordTimings` likewise — neither is read by the list window.
    @ViewBuilder
    private var analysisSummary: some View {
        if entry.coachAnalyzedAt == nil && entry.objectiveAnalyzedAt == nil {
            Label("Not reviewed by the Coach yet", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let result = entry.pronunciationResult {
            let lessons = PronunciationSummary.lessons(from: result)
            if !lessons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SOUNDS TO WORK ON")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(lessons) { lesson in
                        lessonRow(lesson)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.windowBackgroundColor).opacity(0.5))
                )
            }
        }
    }

    private func lessonRow(_ lesson: PronunciationLesson) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline(for: lesson))
                    .font(.subheadline.weight(.medium))
                if !lesson.exampleWords.isEmpty {
                    Text("in " + lesson.exampleWords.map { "“\($0)”" }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A soft, human headline for one weak sound: name the substitution the speaker
    /// made when there is one, otherwise frame it as "unclear".
    private func headline(for lesson: PronunciationLesson) -> String {
        if let actual = lesson.actual {
            return "/\(lesson.expected)/ — sounded like /\(actual)/"
        } else if let leading = lesson.leadingObserved {
            return "/\(lesson.expected)/ — unclear, more like /\(leading)/"
        } else {
            return "/\(lesson.expected)/ — unclear"
        }
    }

    // MARK: - Actions

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        withAnimation { showCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopied = false }
        }
    }

    private func togglePlayback() {
        if isPlaying { stopPlayback(); return }
        guard let url = audioURL else { return }
        let controller = AudioPlayerController()
        do {
            try controller.play(url: url)
            audioController = controller
            isPlaying = true
            Task { @MainActor in
                await controller.waitForPlaybackToFinish()
                // Only clear if this is still the active controller.
                if audioController === controller {
                    isPlaying = false
                    audioController = nil
                }
            }
        } catch {
            HexLog.history.error("Failed to play audio: \(error.localizedDescription)")
        }
    }

    private func stopPlayback() {
        audioController?.stop()
        audioController = nil
        isPlaying = false
    }

    private func performDelete() {
        stopPlayback()
        MacTranscriptDeletion.delete(entry, in: modelContext)
        onDelete()
    }
}
