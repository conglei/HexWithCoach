//
//  MacHistoryView.swift
//  VocoMac
//
//  Companion-window "History" section (MC-R8). The native macOS counterpart to the
//  iOS HS-1 / HS-2 surfaces: a Notes|Dictation segmented control over a windowed,
//  searchable browse of the lean `TranscriptEntry` row.
//
//  HS-1 — the mixed list is split into Notes | Dictation; default Notes; the last
//  selection is remembered via @AppStorage; each segment has its own empty state.
//
//  HS-2 — the list never loads the whole table. Date-scope chips (This week / This
//  month / All) bound a windowed fetch (predicate `date >= scopeStart` +
//  `fetchLimit ~50`) and double as pagination — "Load older" extends the window.
//  Search is its own bounded fetch across *all* scopes so older matches stay
//  reachable regardless of the active chip.
//
//  The bounded fetch lives in `MacHistoryList`, which declares a parameterized
//  `@Query` built in its `init` and is recreated via `.id(...)` whenever the scope /
//  segment / search / limit changes — preserving SwiftData's auto-update reactivity
//  while bounding memory. Crucially, the list/window path reads only lean-row fields
//  and NEVER faults the heavy `TranscriptAnalysis` sidecar; that happens only in the
//  detail view (`MacTranscriptDetailView`) when a transcript is opened.
//
//  The shared `ModelContainer` is injected into the environment by `HexAppDelegate`
//  (`presentMainWindow()`), so `@Query` and `@Environment(\.modelContext)` here read
//  the same SwiftData store the TCA capture pipeline writes to (MC-R3).
//

import AppKit
import SwiftData
import SwiftUI
import VocoCore

struct MacHistoryView: View {
    /// Persisted so History reopens on the segment the user last browsed (HS-1).
    @AppStorage("voco.mac.history.segment") private var segment: MacHistorySegment = .notes
    /// Active date-scope chip; bounds the windowed fetch (HS-2). Default This week.
    @State private var scope: MacHistoryScope = .week
    /// How many rows the current window may materialize. "Load older" raises this;
    /// switching segment/scope/search resets it back to the base page (HS-2).
    @State private var limit = MacHistoryScope.pageSize
    @State private var query = ""
    /// The currently open transcript, driving the detail column.
    @State private var selected: TranscriptEntry?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Transcript kind", selection: $segment) {
                ForEach(MacHistorySegment.allCases) { seg in
                    Text(seg.title).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Scope chips are hidden while searching — search spans all scopes, so a
            // bounding chip would be misleading.
            if query.isEmpty {
                scopeChips
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()

            MacHistoryList(
                segment: segment,
                scope: scope,
                searchText: query,
                limit: limit,
                selected: $selected,
                onLoadOlder: { limit += MacHistoryScope.pageSize }
            )
            // Recreate the subview (and its parameterized @Query) whenever the window
            // inputs change so the bounded fetch re-runs.
            .id(MacWindowKey(segment: segment, scope: scope, search: query, limit: limit))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search transcripts")
        // Reset the window whenever the segment / scope / search changes so we don't
        // carry an inflated "Load older" limit across surfaces.
        .onChange(of: segment) { _, _ in limit = MacHistoryScope.pageSize; selected = nil }
        .onChange(of: scope) { _, _ in limit = MacHistoryScope.pageSize }
        .onChange(of: query) { _, _ in limit = MacHistoryScope.pageSize }
        .inspector(isPresented: .constant(selected != nil)) {
            if let selected {
                MacTranscriptDetailView(entry: selected) { self.selected = nil }
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Scope chips (HS-2)

    private var scopeChips: some View {
        HStack(spacing: 8) {
            ForEach(MacHistoryScope.allCases) { scopeOption in
                Button {
                    scope = scopeOption
                } label: {
                    Text(scopeOption.title)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                scope == scopeOption
                                    ? Color.accentColor.opacity(0.18)
                                    : Color(.unemphasizedSelectedContentBackgroundColor).opacity(0.4)
                            )
                        )
                        .foregroundStyle(scope == scopeOption ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Segment / scope / window key

/// The selected History surface (HS-1). Notes and Dictation read as distinct
/// surfaces even though they share one underlying model.
enum MacHistorySegment: String, CaseIterable, Identifiable {
    case notes
    case dictation

    var id: String { rawValue }
    var title: String { self == .notes ? "Notes" : "Dictation" }
    var kind: TranscriptKind { self == .notes ? .note : .dictation }
}

/// Date-scope chips that double as pagination (HS-2). Each bounds the windowed
/// fetch to `date >= scopeStart`; `.all` removes the lower bound.
enum MacHistoryScope: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    /// Base window size, and the increment "Load older" adds each tap (~50).
    static let pageSize = 50

    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: return "This week"
        case .month: return "This month"
        case .all: return "All"
        }
    }

    /// Lower bound for the fetch predicate, or nil for `.all` (no bound).
    func start(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: now)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        case .all: return nil
        }
    }
}

/// Stable identity for the active window. Changing any field recreates
/// `MacHistoryList` (via `.id`), re-running its parameterized `@Query`.
private struct MacWindowKey: Hashable {
    let segment: MacHistorySegment
    let scope: MacHistoryScope
    let search: String
    let limit: Int
}

// MARK: - Windowed list

/// Bounded, day-grouped transcript list. Declares a parameterized `@Query` in
/// `init` (predicate + sort + `fetchLimit`) so SwiftData materializes only the
/// active window while still auto-updating on inserts/edits within it. Reads only
/// lean-row fields — it never touches `analysis`, so the heavy sidecar stays faulted.
private struct MacHistoryList: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [TranscriptEntry]

    private let segment: MacHistorySegment
    private let isSearching: Bool
    /// Whether the window may hold more rows than it currently shows (fetch hit its
    /// limit), so "Load older" can reveal more.
    private let mayHaveMore: Bool
    private let onLoadOlder: () -> Void
    @Binding private var selected: TranscriptEntry?

    @State private var pendingDelete: TranscriptEntry?

    init(
        segment: MacHistorySegment,
        scope: MacHistoryScope,
        searchText: String,
        limit: Int,
        selected: Binding<TranscriptEntry?>,
        onLoadOlder: @escaping () -> Void
    ) {
        self.segment = segment
        self._selected = selected
        self.onLoadOlder = onLoadOlder

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isSearching = !trimmed.isEmpty
        self.mayHaveMore = trimmed.isEmpty && scope != .all

        let kindRaw = segment.kind.rawValue
        // Search spans *all* scopes (no date lower bound) so older matches stay
        // reachable; otherwise bound by the active chip's start date.
        let scopeStart = trimmed.isEmpty ? scope.start() : nil

        let predicate: Predicate<TranscriptEntry>
        if !trimmed.isEmpty {
            if let scopeStart {
                predicate = #Predicate { $0.kindRaw == kindRaw && $0.date >= scopeStart && $0.text.localizedStandardContains(trimmed) }
            } else {
                predicate = #Predicate { $0.kindRaw == kindRaw && $0.text.localizedStandardContains(trimmed) }
            }
        } else if let scopeStart {
            predicate = #Predicate { $0.kindRaw == kindRaw && $0.date >= scopeStart }
        } else {
            predicate = #Predicate { $0.kindRaw == kindRaw }
        }

        var descriptor = FetchDescriptor<TranscriptEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        _entries = Query(descriptor)
    }

    private var grouped: [(day: Date, entries: [TranscriptEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: entries) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                if isSearching {
                    ContentUnavailableView.search
                } else {
                    emptyState
                }
            } else {
                List(selection: $selected) {
                    ForEach(grouped, id: \.day) { group in
                        Section(dayHeader(group.day)) {
                            ForEach(group.entries) { entry in
                                row(entry)
                                    .tag(entry)
                                    .contextMenu { rowMenu(entry) }
                            }
                        }
                    }
                    loadOlderRow
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Delete this transcript?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                if selected?.id == entry.id { selected = nil }
                MacTranscriptDeletion.delete(entry, in: modelContext)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("Its audio and any coaching cards, observations, and progress for it are removed too. This can't be undone.")
        }
    }

    // MARK: - Rows

    /// One transcript row — lean: text preview + kind icon + time. No `analysis`.
    private func row(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: entry.kind.systemImage)
                    .foregroundStyle(Color.accentColor)
                if let app = entry.sourceAppName { Text(app); Text("·") }
                Text(entry.date, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func rowMenu(_ entry: TranscriptEntry) -> some View {
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
        }
        Button("Delete", role: .destructive) { pendingDelete = entry }
    }

    /// "Load older" appears only when not searching and the window is bounded —
    /// `.all` with no date bound is already the full history.
    @ViewBuilder
    private var loadOlderRow: some View {
        if mayHaveMore {
            Button(action: onLoadOlder) {
                Text("Load older")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
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
}
