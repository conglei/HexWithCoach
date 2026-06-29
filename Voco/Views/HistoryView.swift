//
//  HistoryView.swift
//  HexIOS
//
//  History tab (locked design §4.4): unified transcript list (notes + keyboard
//  insertions), day-grouped, searchable. Backed by SwiftData (@Query), so it
//  persists across launches and syncs via CloudKit. Restyled with the shared
//  HexTheme — each transcript is a white rounded card on a grouped background.
//  Inline audio playback is a later add (P4-3).
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    /// Owned by ContentView so "See all" from Home can reset it to the list root.
    @Binding var path: NavigationPath
    @Query(sort: \TranscriptEntry.date, order: .reverse) private var entries: [TranscriptEntry]
    @Query private var allCards: [CoachCardEntity]
    @State private var query = ""
    /// Persisted so the History tab reopens on the segment the user last browsed.
    @AppStorage("hex.history.segment") private var segment: HistorySegment = .notes

    /// Which `kind` the selected segment surfaces. HS-1: Notes and Dictation read
    /// as distinct surfaces even though they share one underlying query.
    private enum HistorySegment: String, CaseIterable, Identifiable {
        case notes
        case dictation

        var id: String { rawValue }
        var title: String { self == .notes ? "Notes" : "Dictation" }
        var kind: TranscriptKind { self == .notes ? .note : .dictation }
    }

    /// Only annotate processed/pending once the Coach has actually run — otherwise
    /// every row would show a confusing "pending" badge when coaching is off.
    private var coachActive: Bool { entries.contains { $0.coachAnalyzedAt != nil } }

    /// Entries for the selected segment only — filtered in-memory over the full
    /// `@Query` for now (HS-2 will add a windowed fetch).
    private var segmentEntries: [TranscriptEntry] {
        entries.filter { $0.kind == segment.kind }
    }

    private var filtered: [TranscriptEntry] {
        let scoped = segmentEntries
        guard !query.isEmpty else { return scoped }
        return scoped.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var grouped: [(day: Date, entries: [TranscriptEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Transcript kind", selection: $segment) {
                    ForEach(HistorySegment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Group {
                    if segmentEntries.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(grouped, id: \.day) { group in
                                    section(group)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .searchable(text: $query, prompt: "Search transcripts")
            .navigationDestination(for: TranscriptEntry.self) { TranscriptDetailView(entry: $0) }
        }
    }

    /// Per-segment empty state — distinguishes "no notes" from "no dictations".
    @ViewBuilder
    private var emptyState: some View {
        switch segment {
        case .notes:
            ContentUnavailableView(
                "No notes yet",
                systemImage: "note.text",
                description: Text("In-app captures show up here.")
            )
        case .dictation:
            ContentUnavailableView(
                "No dictations yet",
                systemImage: "keyboard",
                description: Text("Keyboard dictations across your apps show up here.")
            )
        }
    }

    // MARK: - Day section

    private func section(_ group: (day: Date, entries: [TranscriptEntry])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayHeader(group.day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            // CI-7: no per-note "Analyze" context menu — coaching runs
            // automatically at capture (objective) and over the backlog (LLM).
            ForEach(group.entries, id: \.persistentModelID) { entry in
                NavigationLink(value: entry) {
                    card(entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "TODAY · JUN 27" — relative when recent, weekday + date otherwise.
    private func dayHeader(_ day: Date) -> String {
        let cal = Calendar.current
        let prefix: String
        if cal.isDateInToday(day) {
            prefix = "Today"
        } else if cal.isDateInYesterday(day) {
            prefix = "Yesterday"
        } else {
            prefix = day.formatted(.dateTime.weekday(.wide))
        }
        let date = day.formatted(.dateTime.month(.abbreviated).day())
        return "\(prefix) · \(date)".uppercased()
    }

    // MARK: - Transcript card

    private func card(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if coachActive { statusIndicator(entry) }
            }

            HStack(spacing: 6) {
                Image(systemName: entry.kind.systemImage)
                    .foregroundStyle(HexTheme.gradientColors[0])
                    .accessibilityLabel(entry.kind.label)
                Text(entry.date, style: .time)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .hexCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether the Coach has processed this transcript, and how many notes it found.
    @ViewBuilder
    private func statusIndicator(_ entry: TranscriptEntry) -> some View {
        if entry.coachAnalyzedAt == nil {
            Image(systemName: "hourglass")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            let count = allCards.filter { $0.transcriptID == entry.id }.count
            if count > 0 {
                Label("\(count)", systemImage: "sparkles")
                    .font(.caption2)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
