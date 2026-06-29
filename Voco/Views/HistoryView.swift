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
//  HS-2: the list no longer loads every row. Date-scope chips (This week /
//  This month / All) bound a windowed fetch (predicate `date >= scopeStart` +
//  fetchLimit), and they double as pagination — "Load older" extends the window.
//  Search is its own bounded fetch across *all* scopes so older matches are
//  reachable regardless of the active chip. The bounded fetch lives in the
//  `HistoryList` subview, which declares a parameterized `@Query` built in its
//  `init` and is recreated via `.id(...)` whenever the scope / segment / search
//  changes — preserving SwiftData's auto-update reactivity while bounding memory.
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    /// Owned by ContentView so "See all" from Home can reset it to the list root.
    @Binding var path: NavigationPath
    @State private var query = ""
    /// Persisted so the History tab reopens on the segment the user last browsed.
    @AppStorage("hex.history.segment") private var segment: HistorySegment = .notes
    /// Active date-scope chip. Bounds the windowed fetch; defaults to This week.
    @State private var scope: HistoryScope = .week
    /// How many rows the current window is allowed to materialize. "Load older"
    /// raises this; switching scope/segment/search resets it back to the base page.
    @State private var limit = HistoryScope.pageSize
    /// HS-3: multi-select bulk-delete mode, toggled by the "Select" toolbar button.
    @State private var editMode: EditMode = .inactive
    /// HS-3: ids checked in Select mode. Lives here (not in the recreated subview)
    /// so it survives "Load older" re-creating `HistoryList`.
    @State private var selection: Set<UUID> = []

    private var isSelecting: Bool { editMode.isEditing }

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

                // Date-scope chips are hidden while searching: search deliberately
                // spans all scopes, so a bounding chip would be misleading.
                if query.isEmpty {
                    scopeChips
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                HistoryList(
                    segment: segment,
                    scope: scope,
                    searchText: query,
                    limit: limit,
                    isSelecting: isSelecting,
                    selection: $selection,
                    onLoadOlder: { limit += HistoryScope.pageSize }
                )
                // Recreate the subview (and thus its parameterized @Query) whenever
                // the window inputs change, so the bounded fetch re-runs.
                .id(WindowKey(segment: segment, scope: scope, search: query, limit: limit))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .searchable(text: $query, prompt: "Search transcripts")
            .navigationDestination(for: TranscriptEntry.self) { TranscriptDetailView(entry: $0) }
            .environment(\.editMode, $editMode)
            .toolbar { selectToolbar }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { bulkDeleteBar }
            }
            // Reset the window whenever the segment or scope changes so we don't
            // carry an inflated "Load older" limit across surfaces.
            .onChange(of: segment) { _, _ in limit = HistoryScope.pageSize; selection.removeAll() }
            .onChange(of: scope) { _, _ in limit = HistoryScope.pageSize }
            .onChange(of: query) { _, _ in limit = HistoryScope.pageSize }
            // Leaving Select mode always clears the checkmarks.
            .onChange(of: isSelecting) { _, selecting in if !selecting { selection.removeAll() } }
        }
    }

    // MARK: - Select mode (HS-3)

    @ToolbarContentBuilder
    private var selectToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button("Done") { editMode = .inactive }
            } else {
                Button("Select") { editMode = .active }
            }
        }
    }

    /// Bottom action bar shown in Select mode: bulk delete the checked rows. The
    /// destructive action confirms first, since notes carry coaching history.
    private var bulkDeleteBar: some View {
        BulkDeleteBar(selection: $selection) { editMode = .inactive }
            .background(.ultraThinMaterial)
    }

    // MARK: - Scope chips

    private var scopeChips: some View {
        HStack(spacing: 8) {
            ForEach(HistoryScope.allCases) { scopeOption in
                Button {
                    scope = scopeOption
                } label: {
                    Text(scopeOption.title)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                scope == scopeOption
                                    ? HexTheme.gradientColors[0].opacity(0.18)
                                    : Color(.secondarySystemGroupedBackground)
                            )
                        )
                        .foregroundStyle(scope == scopeOption ? HexTheme.gradientColors[0] : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

/// The selected History surface. HS-1: Notes and Dictation read as distinct
/// surfaces even though they share one underlying model.
enum HistorySegment: String, CaseIterable, Identifiable {
    case notes
    case dictation

    var id: String { rawValue }
    var title: String { self == .notes ? "Notes" : "Dictation" }
    var kind: TranscriptKind { self == .notes ? .note : .dictation }
}

/// Date-scope chips that double as pagination (HS-2). Each bounds the windowed
/// fetch to `date >= scopeStart`; `.all` removes the lower bound.
enum HistoryScope: String, CaseIterable, Identifiable {
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
/// `HistoryList` (via `.id`), re-running its parameterized `@Query`.
private struct WindowKey: Hashable {
    let segment: HistorySegment
    let scope: HistoryScope
    let search: String
    let limit: Int
}

/// Bounded, day-grouped transcript list. Declares a parameterized `@Query` in
/// `init` (predicate + sort + fetchLimit) so SwiftData materializes only the
/// active window while still auto-updating on inserts/edits within it.
private struct HistoryList: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [TranscriptEntry]
    @Query private var allCards: [CoachCardEntity]

    private let segment: HistorySegment
    private let isSearching: Bool
    private let onLoadOlder: () -> Void
    /// Whether the window may hold more rows than it currently shows — i.e. the
    /// fetch hit its limit, so "Load older" can reveal more.
    private let mayHaveMore: Bool
    /// HS-3: in multi-select mode rows show a checkbox + tap toggles selection
    /// instead of navigating; swipe-to-delete is suppressed.
    private let isSelecting: Bool
    @Binding private var selection: Set<UUID>

    /// HS-3: the single row pending swipe-delete confirmation, if any.
    @State private var pendingDelete: TranscriptEntry?

    init(
        segment: HistorySegment,
        scope: HistoryScope,
        searchText: String,
        limit: Int,
        isSelecting: Bool,
        selection: Binding<Set<UUID>>,
        onLoadOlder: @escaping () -> Void
    ) {
        self.segment = segment
        self.isSelecting = isSelecting
        self._selection = selection
        self.onLoadOlder = onLoadOlder
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isSearching = !trimmed.isEmpty
        self.mayHaveMore = !trimmed.isEmpty ? false : (scope != .all)

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
        descriptor.fetchLimit = limit
        _entries = Query(descriptor)
    }

    /// Only annotate processed/pending once the Coach has actually run — otherwise
    /// every row would show a confusing "pending" badge when coaching is off.
    private var coachActive: Bool { entries.contains { $0.coachAnalyzedAt != nil } }

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
                // A plain List (not the prior ScrollView/LazyVStack) so swipe-to-delete
                // and Select-mode multi-select come for free (HS-3); the card look is
                // preserved via clear row backgrounds + hidden separators.
                List {
                    ForEach(grouped, id: \.day) { group in
                        section(group)
                    }
                    loadOlderRow
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
            }
        }
        // Notes carry coaching history, so a single-row delete confirms first.
        .confirmationDialog(
            "Delete this transcript?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                TranscriptDeletion.delete(entry, in: modelContext)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("Its audio and any coaching cards, observations, and progress for it are removed too. This can't be undone.")
        }
    }

    /// "Load older" appears only when not searching and the window is bounded —
    /// `.all` with no date bound is already the full history. A borderless List row.
    @ViewBuilder
    private var loadOlderRow: some View {
        if mayHaveMore {
            Button(action: onLoadOlder) {
                Text("Load older")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HexTheme.gradientColors[0])
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20))
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
        Section {
            // CI-7: no per-note "Analyze" context menu — coaching runs
            // automatically at capture (objective) and over the backlog (LLM).
            ForEach(group.entries, id: \.persistentModelID) { entry in
                row(entry)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    // Swipe-to-delete is suppressed in Select mode (taps toggle the
                    // checkbox there); the swipe defers to the confirm dialog.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !isSelecting {
                            Button(role: .destructive) {
                                pendingDelete = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
        } header: {
            Text(dayHeader(group.day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 4, trailing: 20))
        }
    }

    /// One transcript row: in Select mode a tappable checkbox + card; otherwise a
    /// navigation link into the detail view.
    @ViewBuilder
    private func row(_ entry: TranscriptEntry) -> some View {
        if isSelecting {
            Button {
                if selection.contains(entry.id) { selection.remove(entry.id) }
                else { selection.insert(entry.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(entry.id) ? HexTheme.gradientColors[0] : .secondary)
                    card(entry)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: entry) {
                card(entry)
            }
            .buttonStyle(.plain)
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

// MARK: - Bulk delete (HS-3 Select mode)

/// Bottom bar shown in Select mode. Confirms, then cascade-deletes every checked
/// transcript (and its satellites) in one batched save. Resolves the checked ids
/// to entries via its own fetch so a selection that spans windows still deletes
/// fully. Exits Select mode after a delete.
private struct BulkDeleteBar: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: Set<UUID>
    let onFinish: () -> Void

    @State private var confirming = false

    private var count: Int { selection.count }

    var body: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                confirming = true
            } label: {
                Label(count == 0 ? "Delete" : "Delete \(count)", systemImage: "trash")
                    .font(.headline)
            }
            .disabled(count == 0)
            Spacer()
        }
        .padding(.vertical, 12)
        .confirmationDialog(
            "Delete \(count) transcript\(count == 1 ? "" : "s")?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete \(count)", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their audio and any coaching cards, observations, and progress are removed too. This can't be undone.")
        }
    }

    private func performDelete() {
        let ids = selection
        guard !ids.isEmpty else { return }
        // Resolve checked ids to live entries (selection can outlive the visible
        // window), then cascade-delete them in one batched save.
        let descriptor = FetchDescriptor<TranscriptEntry>(predicate: #Predicate { ids.contains($0.id) })
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        TranscriptDeletion.delete(entries, in: modelContext)
        selection.removeAll()
        onFinish()
    }
}
