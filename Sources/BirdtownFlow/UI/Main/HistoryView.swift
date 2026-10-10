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
///
/// Behaves like a Mac list once it has focus: click, ⌘-click and ⇧-click select; ↑/↓ (with ⇧
/// to extend) move; ⌘A selects everything listed; ⌘C copies the selected transcripts; Return
/// pastes the selected one again; Delete deletes (with undo); Esc clears the selection.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query: String
    /// What the list is searching for: `query` once typing pauses, so each keystroke doesn't
    /// rescan every dictation. Clearing applies straight away.
    @State private var appliedQuery: String
    @State private var filter: HistoryFilter = .all
    @State private var selection = ListSelection<UUID>()
    @State private var highlighted: UUID?
    /// A revealed row to scroll to once the list shows it.
    @State private var scrollTarget: UUID?
    /// The selection a "Delete N dictations?" confirmation is about.
    @State private var bulkDeletion: Set<UUID> = []
    @State private var isConfirmingBulkDelete = false
    @State private var player = AudioPlayback()
    @State private var searchMemo = ViewMemo<SearchKey, SearchResult>()
    @State private var listMemo = ViewMemo<ListKey, ListResult>()
    @FocusState private var listFocused: Bool

    private let originalRecordID: UUID?

    init(initialQuery: String = "", originalRecordID: UUID? = nil, initialSelection: [UUID] = []) {
        _query = State(initialValue: initialQuery)
        _appliedQuery = State(initialValue: initialQuery)
        var selection = ListSelection<UUID>()
        selection.selectAll(initialSelection)
        _selection = State(initialValue: selection)
        self.originalRecordID = originalRecordID
    }

    var body: some View {
        // Selecting, highlighting and playing re-run body too; only a new search, filter or
        // history change redoes the search and the grouping. Deletes still inside their undo
        // window are hidden (see `AppModel.historyDeletion`), as are the rows of recordings
        // still in progress, and a new or undone delete or a row handed over changes the key,
        // so the memo never serves a list with them in it or missing.
        let searchKey = SearchKey(records: model.history.records, query: appliedQuery, hidden: model.historyDeletion.hidden)
        let result = searchMemo.value(for: searchKey) { key in
            Self.runSearch(key, in: model.history)
        }
        let list = listMemo.value(for: ListKey(search: searchKey, filter: filter)) { key in
            let visible = result.searched.filter(key.filter.matches)
            return ListResult(visible: visible, order: visible.map(\.id), days: HistoryDay.group(visible))
        }
        let visible = list.visible
        let order = list.order
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l, pinnedViews: [.sectionHeaders]) {
                    header(counts: result.counts, rollup: result.rollup)
                        .padding(.bottom, Spacing.xs)
                    if visible.isEmpty {
                        emptyState(searchMatches: result.searched.count)
                    } else {
                        ForEach(list.days) { day in
                            Section {
                                dayCard(day, order: order)
                            } header: {
                                dayHeader(day)
                            }
                        }
                    }
                }
                .pageLayout()
            }
            // The floating bar covers the bottom of the list; room to scroll the last row clear.
            .contentMargins(.bottom, showsBottomBar(order: order) ? Layout.Main.floatingBarClearance : 0, for: .scrollContent)
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            // Only what's on screen: a search may have hidden rows selected earlier.
            .onDeleteCommand { requestDelete(Set(selection.ordered(in: order))) }
            .onExitCommand { selection.clear() }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                move(press.key == .upArrow ? -1 : 1, extending: press.modifiers.contains(.shift),
                     order: order, proxy: proxy)
            }
            .onKeyPress(.return) { pasteAgain(order: order, records: visible) }
            // Edit › Copy and Select All, so the menu items light up and show their shortcuts.
            .onCopyCommand(perform: copyCommand(order: order, records: visible))
            .onCommand(#selector(NSText.selectAll(_:))) {
                selection.selectAll(order)
            }
            // Like Finder: rows a search or filter hides drop out of the selection; rows that
            // stay listed stay selected (so a reveal that clears the search keeps its row).
            // The applied query, not the field: the list only changes once typing pauses.
            .onChange(of: appliedQuery) { _, _ in selection.prune(to: order) }
            .onChange(of: filter) { _, _ in selection.prune(to: order) }
            .onChange(of: model.focusedRecordID, initial: true) { _, id in
                reveal(id)
            }
            // Scroll once the list has been rebuilt: a reveal may have just cleared the search
            // or filter (the row wasn't listed yet), or the page may be appearing for it.
            .task(id: scrollTarget) {
                guard let id = scrollTarget else { return }
                await Task.yield()
                withAnimation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                scrollTarget = nil
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
        .overlay(alignment: .bottom) { bottomBar(order: order, records: visible) }
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: model.historyDeletion.pending)
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: selection.count > 1)
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: filter)
        .confirmationDialog(
            "Delete \(bulkDeletion.count) dictations?",
            isPresented: $isConfirmingBulkDelete
        ) {
            Button("Delete \(bulkDeletion.count) Dictations", role: .destructive) { delete(bulkDeletion) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can undo this for a few seconds. Their audio is deleted too.")
        }
        // A pending delete outlives the page (Home shows the same Undo); only playback stops.
        .onDisappear { player.stop() }
    }

    // MARK: - Header

    private var showsTimings: Bool { model.settings.historyShowsTimings }

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

    private func header(counts: [HistoryFilter: Int], rollup: TimingRollup?) -> some View {
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
                    let count = option == .all ? nil : counts[option, default: 0]
                    FilterChip(
                        title: option.title,
                        symbol: option.symbol,
                        count: count,
                        isSelected: filter == option
                    ) {
                        filter = option
                    }
                    // Still clickable (its empty state explains), but it shouldn't look as
                    // inviting as a chip with something behind it.
                    .opacity(count == 0 && filter != option ? Interaction.dimmedOpacity : 1)
                }
                Spacer(minLength: Spacing.s)
                // A view, not a filter: it sits apart from the chips and keeps every row listed.
                FilterChip(title: "Timings", symbol: "stopwatch", isSelected: showsTimings) {
                    model.settings.historyShowsTimings.toggle()
                }
                .help(showsTimings
                      ? "Hide how long each dictation took"
                      : "Show how long transcription, polish and the rest took, in milliseconds")
                .accessibilityLabel("Show timings")
            }
            if showsTimings, let rollup {
                // p50 is a typical dictation, p90 a slow one.
                Text(rollup.summary(format: OriginalPanel.format))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .monospacedDigit()
                    .help("Typical (p50) and slow (p90) times over your most recent dictations that were "
                        + "typed or copied, measured from when you let go of the key")
            }
        }
    }

    // MARK: - List

    private func dayCard(_ day: HistoryDay, order: [UUID]) -> some View {
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
                    // What the list matched, so highlights agree with the rows shown.
                    query: appliedQuery,
                    showsTimings: showsTimings,
                    onSelect: { click in select(record.id, click, order: order) },
                    onDelete: {
                        requestDelete(selection.contains(record.id)
                            ? Set(selection.ordered(in: order))
                            : [record.id])
                    }
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
        // Records waiting out the undo window, or still being recorded, are hidden but in the store.
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
                        Button("Clear Search") { clearQuery() }
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

    // MARK: - Bottom bar

    /// Whether `bottomBar` shows anything: the undo toast or the selection bar.
    private func showsBottomBar(order: [UUID]) -> Bool {
        !model.historyDeletion.pending.isEmpty || selection.ordered(in: order).count > 1
    }

    /// The undo toast while a delete can be undone; otherwise, with several rows selected,
    /// what can be done to them all.
    @ViewBuilder
    private func bottomBar(order: [UUID], records: [HistoryRecord]) -> some View {
        let selected = selection.ordered(in: order)
        if !model.historyDeletion.pending.isEmpty {
            HistoryUndoToast()
        } else if selected.count > 1 {
            HistoryFloatingBar {
                Text("\(selected.count) selected")
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Button("Copy") { copy(order: order, records: records) }
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
                    .help("Copy the selected dictations (⌘C)")
                Button("Delete…") { requestDelete(Set(selected)) }
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
                    .help("Delete the selected dictations (⌫)")
                IconButton(symbol: "xmark", label: "Clear Selection") { selection.clear() }
                    .help("Clear the selection (Esc)")
            }
        }
    }

    // MARK: - Actions

    private func select(_ id: UUID, _ click: ListSelection<UUID>.Click, order: [UUID]) {
        selection.click(id, click, in: order)
        listFocused = true
    }

    private func move(_ step: Int, extending: Bool, order: [UUID], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let target = selection.move(step, in: order, extending: extending) else { return .ignored }
        // No anchor: scroll only as far as it takes to bring the row into view.
        withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
            proxy.scrollTo(target)
        }
        return .handled
    }

    /// Return: paste the one selected dictation again, as its Paste Again button does.
    private func pasteAgain(order: [UUID], records: [HistoryRecord]) -> KeyPress.Result {
        // Only from the list itself: Return in the search field must never paste.
        guard listFocused,
              let id = selection.single(in: order),
              let record = records.first(where: { $0.id == id }),
              record.hasText
        else { return .ignored }
        model.controller.insert(record)
        return .handled
    }

    /// The selected transcripts, top to bottom, separated by blank lines.
    private func selectedText(order: [UUID], records: [HistoryRecord]) -> String? {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let texts = selection.ordered(in: order)
            .compactMap { byID[$0] }
            .filter(\.hasText)
            .map(\.finalText)
        return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }

    /// ⌘C's handler, or `nil` (Copy greyed out) when nothing listed is selected.
    private func copyCommand(order: [UUID], records: [HistoryRecord]) -> (() -> [NSItemProvider])? {
        guard !selection.ordered(in: order).isEmpty else { return nil }
        return {
            guard let text = selectedText(order: order, records: records) else { return [] }
            announceCopied(order: order)
            return [NSItemProvider(object: text as NSString)]
        }
    }

    private func copy(order: [UUID], records: [HistoryRecord]) {
        guard let text = selectedText(order: order, records: records) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        announceCopied(order: order)
    }

    private func announceCopied(order: [UUID]) {
        let count = selection.ordered(in: order).count
        AccessibilityNotification.Announcement(count == 1 ? "Copied" : "Copied \(count) dictations").post()
    }

    /// One dictation deletes straight away (with undo); several ask first.
    private func requestDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if ids.count > 1 {
            bulkDeletion = ids
            isConfirmingBulkDelete = true
        } else {
            delete(ids)
        }
    }

    private func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        HistoryUndoToast.delete(ids, model: model, player: player)
        selection.remove(ids)
        bulkDeletion = []
    }

    /// Scrolls to a record opened from elsewhere (Home, the HUD, the menu bar), selects it so
    /// the keyboard carries on from there, and flashes it.
    private func reveal(_ id: UUID?) {
        guard let id else { return }
        model.focusedRecordID = nil
        guard model.history.record(id: id) != nil, !model.historyDeletion.isHidden(id) else { return }
        if !visibleIDs.contains(id) {
            clearQuery()
            filter = .all
        }
        selection.select(id)
        listFocused = true
        scrollTarget = id
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
        /// Matches for the search, minus hidden records (`HistoryDeletion.hidden`).
        let searched: [HistoryRecord]
        /// How many of `searched` each chip would show.
        let counts: [HistoryFilter: Int]
        /// The Timings view's line about recent dictations, over every record but hidden
        /// ones, whatever the search.
        let rollup: TimingRollup?
    }

    private struct ListKey: Equatable {
        let search: SearchKey
        let filter: HistoryFilter
    }

    private struct ListResult {
        let visible: [HistoryRecord]
        /// `visible`'s ids, top to bottom: what selection and the keyboard move through.
        let order: [UUID]
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
        let rollup = TimingRollup.recent(key.records.lazy.filter { !key.hidden.contains($0.id) })
        return SearchResult(searched: searched, counts: counts, rollup: rollup)
    }
}
