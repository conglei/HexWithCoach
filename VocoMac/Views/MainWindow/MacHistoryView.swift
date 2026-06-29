//
//  MacHistoryView.swift
//  VocoMac
//
//  Companion-window "History" section (MC-R8, redesigned MC-R12). The native macOS
//  counterpart to the iOS HS-1 / HS-2 surfaces: a Notes|Dictation segmented control
//  over a windowed, searchable browse of the lean `TranscriptEntry` row.
//
//  MC-R12 — the Mail/master-detail pattern. A nested `NavigationSplitView` lives
//  inside the History pane: a NARROW transcript-list sidebar
//  (`.navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)`) leading, and
//  a DOMINANT `MacTranscriptDetailView` detail trailing that fills the rest. The
//  list column owns its own controls — the Notes|Dictation segment, the date-scope
//  chips, the search field, and the list-wide actions (copy-all / delete-all) — all
//  in its own header, never floating in the window titlebar. The detail's per-note
//  actions (copy, delete) live in the detail's own toolbar. When nothing is
//  selected the detail shows a "Select a transcript" placeholder.
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
    /// Defaults to **Dictation** on macOS: the Mac's primary capture is the
    /// always-on hotkey (cross-app dictation), so opening on Notes would show an
    /// empty list for most users. (iOS defaults to Notes, where in-app notes lead.)
    @AppStorage("voco.mac.history.segment") private var segment: MacHistorySegment = .dictation
    /// Active date-scope chip; bounds the windowed fetch (HS-2). Default This week.
    @State private var scope: MacHistoryScope = .week
    /// How many rows the current window may materialize. "Load older" raises this;
    /// switching segment/scope/search resets it back to the base page (HS-2).
    @State private var limit = MacHistoryScope.pageSize
    @State private var query = ""
    /// The currently open transcript, driving the detail column.
    @State private var selected: TranscriptEntry?

    var body: some View {
        // Master-detail (MC-R12): a NARROW transcript-list sidebar leading, a
        // DOMINANT detail trailing. Nested inside the window's own split view; the
        // inner sidebar carries ALL list-scoped controls so nothing floats in the
        // window titlebar.
        NavigationSplitView {
            listColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            if let selected {
                MacTranscriptDetailView(entry: selected) { self.selected = nil }
            } else {
                placeholder
            }
        }
        // Reset the window whenever the segment / scope / search changes so we don't
        // carry an inflated "Load older" limit across surfaces.
        .onChange(of: segment) { _, _ in limit = MacHistoryScope.pageSize; selected = nil }
        .onChange(of: scope) { _, _ in limit = MacHistoryScope.pageSize }
        .onChange(of: query) { _, _ in limit = MacHistoryScope.pageSize }
    }

    // MARK: - List column (owns all list-scoped controls)

    private var listColumn: some View {
        VStack(spacing: 0) {
            Picker("Transcript kind", selection: $segment) {
                ForEach(MacHistorySegment.allCases) { seg in
                    Text(seg.title).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search lives WITH the list (not the window toolbar) so it never floats.
            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Scope chips are hidden while searching — search spans all scopes, so a
            // bounding chip would be misleading.
            if query.isEmpty {
                scopeChips
                    .padding(.horizontal, 12)
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
        // No list-column nav title: the outer sidebar already labels this surface
        // "History", and the Notes|Dictation segment names the list. A "Transcript"
        // (singular) or duplicate "History" title here just mislabels the list (MC-R13).
    }

    /// A plain search field that sits in the list header — deliberately NOT
    /// `.searchable(placement: .toolbar)`, which renders floating in the window
    /// titlebar (the bug we're fixing).
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(.textBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Detail placeholder

    private var placeholder: some View {
        ContentUnavailableView(
            "Select a transcript",
            systemImage: "text.bubble",
            description: Text("Pick a note or dictation on the left to read it and see its coaching.")
        )
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
    /// Confirmation for the list-wide "Delete all" action over the current window.
    @State private var confirmingDeleteAll = false

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
        VStack(spacing: 0) {
            // List-wide actions live WITH the list (not the window titlebar): a
            // count and the copy-all / delete-all controls over the current window.
            if !entries.isEmpty {
                listActionBar
                Divider()
            }

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
        }
        .confirmationDialog(
            "Delete all shown transcripts?",
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete \(entries.count)", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the \(entries.count) transcript(s) currently shown — their audio and any coaching cards, observations, and progress too. This can't be undone.")
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

    // MARK: - List-wide actions (live with the list, not the window titlebar)

    /// A compact bar above the list: a quiet caption plus a `•••` menu of list-scoped
    /// actions (copy-all / delete-all) with TEXT labels. Routing these through a menu
    /// keeps them visually distinct from the per-note copy/delete (which live in the
    /// detail's own toolbar) — no bare trash icon that could be mistaken for
    /// "delete this" (MC-R13).
    private var listActionBar: some View {
        HStack(spacing: 8) {
            Text(countCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button {
                    copyAll()
                } label: {
                    Label("Copy all", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    confirmingDeleteAll = true
                } label: {
                    Label("Delete all…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("List actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Humanized count — folds the window size into a quiet caption instead of the
    /// dev-speak "N shown".
    private var countCaption: String {
        let noun = segment == .notes ? "note" : "dictation"
        return "\(entries.count) \(noun)\(entries.count == 1 ? "" : "s")"
    }

    private func copyAll() {
        let joined = entries.map(\.text).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joined, forType: .string)
    }

    private func deleteAll() {
        let doomed = entries
        if let sel = selected, doomed.contains(where: { $0.id == sel.id }) { selected = nil }
        for entry in doomed {
            MacTranscriptDeletion.delete(entry, in: modelContext)
        }
    }

    // MARK: - Rows

    /// One transcript row — lean and decluttered (MC-R13): the transcript text
    /// leads, then a quiet timestamp. The source app is demoted to an optional
    /// subtle chip rather than a repeated icon + name on every row. No `analysis`.
    private func row(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text(entry.date, style: .time)
                if let app = entry.sourceAppName {
                    sourceChip(app)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// A subtle, low-noise source chip — quieter than the old icon + plain name.
    private func sourceChip(_ app: String) -> some View {
        Text(app)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Color.secondary.opacity(0.12))
            )
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
