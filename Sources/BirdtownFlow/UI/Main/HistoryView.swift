import Accessibility
import AppKit
import MurmurKit
import SwiftUI

/// Narrow History to the dictations you're looking for.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case failed
    case corrected
    case polished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .failed: "Failed"
        case .corrected: "Replaced"
        case .polished: "Polished"
        }
    }

    var symbol: String? {
        switch self {
        case .all: nil
        case .failed: "exclamationmark.triangle"
        case .corrected: "character.book.closed"
        case .polished: "sparkles"
        }
    }

    func matches(_ record: HistoryRecord) -> Bool {
        switch self {
        case .all: true
        case .failed: record.outcome == .failed
        case .corrected: !record.corrections.isEmpty
        case .polished: record.polishedBy.map { $0 != .off } ?? false
        }
    }
}

/// Dictations that happened on one calendar day.
struct HistoryDay: Identifiable {
    let day: Date
    var records: [HistoryRecord]

    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let daysAgo = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: Date())).day ?? 0
        if daysAgo < 7 { return day.formatted(.dateTime.weekday(.wide)) }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.month(.wide).day())
        }
        return day.formatted(.dateTime.month(.wide).day().year())
    }

    /// Groups newest-first records into days, newest day first.
    static func group(_ records: [HistoryRecord], calendar: Calendar = .current) -> [HistoryDay] {
        var days: [HistoryDay] = []
        for record in records {
            let day = calendar.startOfDay(for: record.createdAt)
            if let last = days.indices.last, days[last].day == day {
                days[last].records.append(record)
            } else {
                days.append(HistoryDay(day: day, records: [record]))
            }
        }
        return days
    }
}

/// Every dictation, searchable and grouped by day, with undoable deletes.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query: String
    /// What the list is searching for: `query` once typing pauses, so each keystroke doesn't
    /// rescan every dictation. Clearing applies straight away.
    @State private var appliedQuery: String
    @State private var filter: HistoryFilter = .all
    @State private var selection: Set<UUID> = []
    @State private var highlighted: UUID?
    /// Deleted but still undoable; hidden from the list until the undo window closes.
    @State private var pendingDeletion: Set<UUID> = []
    @State private var commitTask: Task<Void, Never>?
    @State private var isConfirmingBulkDelete = false
    @State private var player = AudioPlayback()
    @State private var searchMemo = ViewMemo<SearchKey, SearchResult>()
    @State private var listMemo = ViewMemo<ListKey, ListResult>()
    @FocusState private var listFocused: Bool

    private let originalRecordID: UUID?

    init(initialQuery: String = "", originalRecordID: UUID? = nil) {
        _query = State(initialValue: initialQuery)
        _appliedQuery = State(initialValue: initialQuery)
        self.originalRecordID = originalRecordID
    }

    var body: some View {
        // Selecting, highlighting and playing re-run body too; only a new search, filter or
        // history change redoes the search and the grouping.
        let searchKey = SearchKey(records: model.history.records, query: appliedQuery, hidden: pendingDeletion)
        let result = searchMemo.value(for: searchKey) { key in
            Self.runSearch(key, in: model.history)
        }
        let list = listMemo.value(for: ListKey(search: searchKey, filter: filter)) { key in
            let visible = result.searched.filter(key.filter.matches)
            return ListResult(visible: visible, days: HistoryDay.group(visible))
        }
        let visible = list.visible
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l, pinnedViews: [.sectionHeaders]) {
                    header(counts: result.counts)
                        .padding(.bottom, Spacing.xs)
                    if visible.isEmpty {
                        emptyState(searchMatches: result.searched.count)
                    } else {
                        ForEach(list.days) { day in
                            Section {
                                dayCard(day)
                            } header: {
                                dayHeader(day)
                            }
                        }
                    }
                }
                .pageLayout()
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            // Only what's on screen: a search may have hidden rows selected earlier.
            .onDeleteCommand { requestDelete(selection.intersection(visible.map(\.id))) }
            .onExitCommand { selection = [] }
            .onChange(of: appliedQuery) { _, _ in selection = [] }
            .onChange(of: filter) { _, _ in selection = [] }
            .onChange(of: model.focusedRecordID, initial: true) { _, id in
                reveal(id, proxy: proxy)
            }
        }
        .task(id: query) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appliedQuery = query
                return
            }
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            appliedQuery = query
        }
        .overlay(alignment: .bottom) { undoToast }
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: pendingDeletion)
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: filter)
        .confirmationDialog(
            "Delete \(selection.count) dictations?",
            isPresented: $isConfirmingBulkDelete
        ) {
            Button("Delete \(selection.count) Dictations", role: .destructive) { delete(selection) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their audio is deleted too.")
        }
        .onDisappear {
            commitPendingDeletion()
            player.stop()
        }
    }

    // MARK: - Header

    /// Matches Settings › Keep audio, so the header never promises audio that isn't kept.
    /// Failed dictations keep theirs regardless, so they can be retried.
    private var subtitle: String {
        switch model.settings.audioRetentionDays {
        case ..<0: "Everything you've dictated, with its audio. Nothing you say is lost."
        case 0: "Everything you've dictated. Audio is kept only for dictations that fail."
        case 1: "Everything you've dictated. Audio is kept for a day."
        case let days: "Everything you've dictated. Audio is kept for \(days) days."
        }
    }

    private func header(counts: [HistoryFilter: Int]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            PageHeader(
                title: "History",
                subtitle: subtitle
            ) {
                SearchField(text: $query, prompt: "Search words or apps")
                    .frame(width: Layout.Main.searchFieldWidth)
            }
            HStack(spacing: Spacing.s) {
                ForEach(HistoryFilter.allCases) { option in
                    FilterChip(
                        title: option.title,
                        symbol: option.symbol,
                        count: option == .all ? nil : counts[option, default: 0],
                        isSelected: filter == option
                    ) {
                        filter = option
                    }
                }
            }
        }
    }

    // MARK: - List

    private func dayCard(_ day: HistoryDay) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(day.records.enumerated()), id: \.element.id) { index, record in
                if index > 0 {
                    RowDivider(leadingInset: HistoryRow.textInset)
                }
                HistoryRow(
                    record: record,
                    player: player,
                    isSelected: selection.contains(record.id),
                    isHighlighted: highlighted == record.id,
                    showsOriginal: record.id == originalRecordID,
                    onSelect: { additive in select(record.id, additive: additive) },
                    onDelete: { requestDelete(selection.contains(record.id) ? selection : [record.id]) }
                )
                .id(record.id)
            }
        }
        .cardSurface()
    }

    private func dayHeader(_ day: HistoryDay) -> some View {
        let words = day.records.reduce(0) { $0 + $1.wordCount }
        return SectionHeader(
            day.title,
            detail: "\(day.records.count) \(day.records.count == 1 ? "dictation" : "dictations") · \(words.formatted()) words"
        )
        .padding(.vertical, Spacing.s)
        // The text lines up with the title and cards; the pinned backing still covers the gutter.
        .background { Palette.canvas.padding(.horizontal, -Spacing.xs) }
    }

    // MARK: - Empty states

    /// Distinguishes "no history at all", "the search matched nothing" and "the search (or
    /// everything) matched, but not this filter" — each needs a different way out.
    @ViewBuilder
    private func emptyState(searchMatches: Int) -> some View {
        // What the list searched for, which can trail the field by a keystroke while typing.
        let trimmed = appliedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Records waiting out the undo window are hidden but still in the store.
        if model.history.records.isEmpty || (trimmed.isEmpty && searchMatches == 0) {
            EmptyState(
                symbol: "waveform",
                title: "Your words will gather here",
                message: "Every dictation lands in History, so you can copy it or paste it again. "
                    + "Hold your shortcut and say something to begin.",
                showsBrandMark: true
            )
        } else if searchMatches == 0 {
            EmptyState(
                symbol: "magnifyingglass",
                title: "Nothing matches “\(trimmed)”",
                message: "Try a shorter phrase, or search for the app you were dictating into."
            ) {
                Button("Clear Search") { clearQuery() }
                    .buttonStyle(.flowSecondary)
            }
        } else if filter == .failed {
            EmptyState(
                symbol: "checkmark",
                title: trimmed.isEmpty ? "Nothing has failed" : "No failed dictations match",
                // With a search, failures may exist outside it: don't claim everything worked.
                message: trimmed.isEmpty
                    ? "Every dictation made it through. If one ever doesn't, it waits here with its audio."
                    : "None of your failed dictations mention “\(trimmed)”."
            ) {
                HStack(spacing: Spacing.s) {
                    if !trimmed.isEmpty {
                        Button("Clear Search") { query = "" }
                            .buttonStyle(.flowSecondary)
                    }
                    Button("Show All") { filter = .all }
                        .buttonStyle(.flowSecondary)
                }
            }
        } else {
            EmptyState(
                symbol: "line.3.horizontal.decrease",
                title: trimmed.isEmpty ? "None of these yet" : "None of these match “\(trimmed)”",
                message: filter == .corrected
                    ? "Dictations your replacements changed will show up here."
                    : "Dictations rewritten by AI polish will show up here."
            ) {
                Button("Show All") { filter = .all }
                    .buttonStyle(.flowSecondary)
            }
        }
    }

    // MARK: - Undo toast

    @ViewBuilder
    private var undoToast: some View {
        if !pendingDeletion.isEmpty {
            HStack(spacing: Spacing.m) {
                Image(systemName: "trash")
                    .foregroundStyle(Palette.inkSecondary)
                Text(pendingDeletion.count == 1 ? "Dictation deleted" : "\(pendingDeletion.count) dictations deleted")
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                Button("Undo") { undoDeletion() }
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityHint("Command-Z")
            }
            .padding(.leading, Spacing.l)
            .padding(.trailing, Spacing.s)
            .padding(.vertical, Spacing.s)
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline))
            .elevation(Elevation.raised)
            .padding(.bottom, Spacing.xl)
            .transition(reduceMotion ? AnyTransition.opacity
                                     : AnyTransition.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func select(_ id: UUID, additive: Bool) {
        if additive {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
        listFocused = true
    }

    /// One dictation deletes straight away (with undo); several ask first.
    private func requestDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if ids.count > 1 {
            selection = ids
            isConfirmingBulkDelete = true
        } else {
            delete(ids)
        }
    }

    private func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        commitPendingDeletion()
        if let playing = player.playingID, ids.contains(playing) { player.stop() }
        pendingDeletion = ids
        selection.subtract(ids)
        // The toast is easy to miss without sight, and it only lasts the undo window.
        let announcement: String = ids.count == 1
            ? "Dictation deleted. Press Command-Z to undo."
            : "\(ids.count) dictations deleted. Press Command-Z to undo."
        AccessibilityNotification.Announcement(announcement).post()
        commitTask = Task {
            try? await Task.sleep(for: Motion.undoWindow)
            guard !Task.isCancelled else { return }
            commitPendingDeletion()
        }
    }

    private func undoDeletion() {
        commitTask?.cancel()
        commitTask = nil
        pendingDeletion = []
    }

    private func commitPendingDeletion() {
        commitTask?.cancel()
        commitTask = nil
        guard !pendingDeletion.isEmpty else { return }
        model.history.delete(ids: pendingDeletion)
        pendingDeletion = []
    }

    /// Scrolls to a record opened from elsewhere (Home, the menu bar) and flashes it.
    private func reveal(_ id: UUID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        model.focusedRecordID = nil
        if model.history.record(id: id) != nil, !visibleIDs.contains(id) {
            clearQuery()
            filter = .all
        }
        withAnimation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion)) {
            proxy.scrollTo(id, anchor: .center)
        }
        highlighted = id
        Task {
            try? await Task.sleep(for: Motion.highlight)
            if highlighted == id {
                withAnimation(Motion.resolve(Motion.fade, reduceMotion: reduceMotion)) { highlighted = nil }
            }
        }
    }

    /// Clears the field and the list together, so a scroll right after finds its row.
    private func clearQuery() {
        query = ""
        appliedQuery = ""
    }

    private var visibleIDs: Set<UUID> {
        Set(model.history.search(appliedQuery).filter(filter.matches).map(\.id))
    }

    // MARK: - Derived

    /// How long typing has to pause before the list searches.
    private static let searchDelay: Duration = .milliseconds(120)

    private struct SearchKey: Equatable {
        let records: [HistoryRecord]
        let query: String
        let hidden: Set<UUID>
    }

    private struct SearchResult {
        /// Matches for the search, minus records waiting out the undo window.
        let searched: [HistoryRecord]
        /// How many of `searched` each chip would show.
        let counts: [HistoryFilter: Int]
    }

    private struct ListKey: Equatable {
        let search: SearchKey
        let filter: HistoryFilter
    }

    private struct ListResult {
        let visible: [HistoryRecord]
        let days: [HistoryDay]
    }

    private static func runSearch(_ key: SearchKey, in history: HistoryStore) -> SearchResult {
        let searched = history.search(key.query).filter { !key.hidden.contains($0.id) }
        // One pass for every chip's count, not one filter per chip.
        var counts: [HistoryFilter: Int] = [:]
        for record in searched {
            for option in HistoryFilter.allCases where option != .all && option.matches(record) {
                counts[option, default: 0] += 1
            }
        }
        return SearchResult(searched: searched, counts: counts)
    }
}
