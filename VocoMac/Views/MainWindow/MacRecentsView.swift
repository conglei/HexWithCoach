//
//  MacRecentsView.swift
//  VocoMac
//
//  Companion-window recents footer — a compact, live "latest captures" surface in
//  the sidebar footer. Capture stays the always-on menu-bar hotkey; this is the
//  glanceable recents list that leans into "macOS = all-day capture hub"
//  (decision 2026-06-29).
//
//  MC-R13: replaced the empty placeholder (which left the rail reading unfinished)
//  with a live, bounded `@Query` of the few newest `TranscriptEntry` rows. Reads
//  only lean-row fields (text + date) — it never faults the heavy
//  `TranscriptAnalysis` sidecar, matching the History list's leanness. Tapping a row
//  hands the selection up so the shell can route to History.
//

import SwiftData
import SwiftUI
import VocoCore

struct MacRecentsView: View {
    /// Called when a recent row is tapped, with the chosen entry, so the shell can
    /// switch sections / open it.
    var onSelect: (TranscriptEntry) -> Void = { _ in }

    /// The few newest captures across both kinds. Bounded so the footer stays
    /// glanceable and the fetch stays cheap. Lean fields only — no `analysis`.
    @Query private var recents: [TranscriptEntry]

    init(onSelect: @escaping (TranscriptEntry) -> Void = { _ in }) {
        self.onSelect = onSelect
        var descriptor = FetchDescriptor<TranscriptEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 4
        _recents = Query(descriptor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recents")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if recents.isEmpty {
                Text("Your latest captures will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(recents) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        recentRow(entry)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func recentRow(_ entry: TranscriptEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entry.kind.systemImage)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(entry.text)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
