//
//  MacTranscriptDetailView.swift
//  VocoMac
//
//  MC-R8: the History detail surface for one `TranscriptEntry`. This is the ONE
//  place that faults the heavy `TranscriptAnalysis` sidecar (word timings /
//  pronunciation) — the list/window path stays lean and never touches `analysis`.
//
//  Mirrors the iOS `TranscriptDetailView` intent natively on macOS, including its
//  **Note | Coaching** segmented lens (MC-R12):
//    • Note (calm default): the plain transcript + audio playback.
//    • Coaching: the teaching layer for THIS note — the GOP-colored layered
//      transcript, "Sounds to work on", and this note's coach cards. Rendered by
//      `MacCoachingLensView`, which reuses the shared VocoCore pieces (the iOS
//      `LayeredTranscriptView` / `CoachIssuesPanel` are iOS-only and not imported).
//
//  Audio playback reuses the macOS `AudioPlayerController` (from `HistoryFeature`).
//  Per-note actions (copy, cascade delete — HS-3 fan-out via `MacTranscriptDeletion`)
//  live in THIS detail view's own toolbar, not the window titlebar. The heavy
//  `TranscriptAnalysis` sidecar (word timings / pronunciation result) is faulted
//  only here, on open — never in the list window.
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

    /// Two reading modes for a note (mirrors iOS). **Note** is the calm default: a
    /// plain transcript + audio. **Coaching** opts in to the teaching layer (GOP
    /// coloring, sounds to work on, coach cards). Read-only either way.
    private enum DetailLens: String, CaseIterable, Identifiable {
        case note = "Note"
        case coaching = "Coaching"
        var id: String { rawValue }
    }
    @State private var lens: DetailLens = .note

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

                // Calm-by-default vs. coaching-detail: Note shows a plain
                // transcript, Coaching reveals the teaching layer (MC-R12).
                Picker("View", selection: $lens) {
                    ForEach(DetailLens.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch lens {
                case .note:
                    Text(entry.text)
                        .font(.title3.weight(.medium))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if audioURL != nil { playbackBar }
                case .coaching:
                    // The coaching layer is faulted only here, on open. Reading the
                    // sidecar / on-row signals never happens in the list window.
                    MacCoachingLensView(entry: entry)

                    if audioURL != nil { playbackBar }
                }
            }
            .padding(20)
        }
        .navigationTitle("Transcript")
        // Re-render the lens subview (and its per-note @Query) when the open
        // transcript changes, and fall back to the calm Note lens.
        .id(entry.id)
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
