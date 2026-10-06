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
        case .corrected: "Edited by dictionary"
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
    @State private var filter: HistoryFilter = .all
    @State private var selection: Set<UUID> = []
    @State private var highlighted: UUID?
    /// Deleted but still undoable; hidden from the list until the undo window closes.
    @State private var pendingDeletion: Set<UUID> = []
    @State private var commitTask: Task<Void, Never>?
    @State private var isConfirmingBulkDelete = false
    @State private var player = AudioPlayback()
    @FocusState private var listFocused: Bool

    private let originalRecordID: UUID?

    init(initialQuery: String = "", originalRecordID: UUID? = nil) {
        _query = State(initialValue: initialQuery)
        self.originalRecordID = originalRecordID
    }

    var body: some View {
        let searched = model.history.search(query).filter { !pendingDeletion.contains($0.id) }
        let visible = searched.filter(filter.matches)
        VStack(spacing: 0) {
            header(searched: searched)
                .frame(maxWidth: Layout.contentMaxWidth)
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.page)
                .padding(.bottom, Spacing.l)
                .frame(maxWidth: .infinity)
            ScrollViewReader { proxy in
                ScrollView {
                    if visible.isEmpty {
                        emptyState
                            .frame(maxWidth: Layout.contentMaxWidth)
                            .frame(maxWidth: .infinity)
                    } else {
                        list(HistoryDay.group(visible))
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onDeleteCommand { requestDelete(selection) }
                .onExitCommand { selection = [] }
                .onChange(of: model.focusedRecordID, initial: true) { _, id in
                    reveal(id, proxy: proxy)
                }
            }
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

    private func header(searched: [HistoryRecord]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            PageHeader(
                title: "History",
                subtitle: "Everything you've dictated, with its audio. Nothing you say is lost."
            ) {
                SearchField(text: $query, prompt: "Search words or apps")
                    .frame(width: Layout.Main.searchFieldWidth)
            }
            HStack(spacing: Spacing.s) {
                ForEach(HistoryFilter.allCases) { option in
                    FilterChip(
                        title: option.title,
                        symbol: option.symbol,
                        count: option == .all ? nil : searched.filter(option.matches).count,
                        isSelected: filter == option
                    ) {
                        filter = option
                    }
                }
            }
        }
    }

    // MARK: - List

    private func list(_ days: [HistoryDay]) -> some View {
        LazyVStack(alignment: .leading, spacing: Spacing.xl, pinnedViews: [.sectionHeaders]) {
            ForEach(days) { day in
                Section {
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
                } header: {
                    dayHeader(day)
                }
            }
        }
        .frame(maxWidth: Layout.contentMaxWidth)
        .padding(.horizontal, Spacing.page)
        .padding(.bottom, Spacing.page)
        .frame(maxWidth: .infinity)
    }

    private func dayHeader(_ day: HistoryDay) -> some View {
        let words = day.records.reduce(0) { $0 + $1.wordCount }
        return SectionHeader(
            day.title,
            detail: "\(day.records.count) \(day.records.count == 1 ? "dictation" : "dictations") · \(words.formatted()) words"
        )
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.xs)
        .background(Palette.canvas)
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.history.records.isEmpty {
            EmptyState(
                symbol: "waveform",
                title: "Your words will gather here",
                message: "Every dictation lands in History with its audio, so you can copy it, paste it "
                    + "again or retry it. Hold your shortcut and say something to begin."
            )
        } else if !trimmed.isEmpty {
            EmptyState(
                symbol: "magnifyingglass",
                title: "Nothing matches “\(trimmed)”",
                message: "Try a shorter phrase, or search for the app you were dictating into."
            ) {
                Button("Clear Search") { query = "" }
                    .buttonStyle(.murmurSecondary)
            }
        } else {
            EmptyState(
                symbol: filter == .failed ? "checkmark" : "line.3.horizontal.decrease",
                title: filter == .failed ? "Nothing has failed" : "Nothing here yet",
                message: filter == .failed
                    ? "Every dictation made it through. If one ever doesn't, it waits here with its audio."
                    : "No dictations match this filter."
            ) {
                Button("Show All") { filter = .all }
                    .buttonStyle(.murmurSecondary)
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
                    .buttonStyle(.murmurGhost)
                    .controlSize(.small)
                    .keyboardShortcut("z", modifiers: .command)
            }
            .padding(.leading, Spacing.l)
            .padding(.trailing, Spacing.s)
            .padding(.vertical, Spacing.s)
            .background(Capsule(style: .continuous).fill(Palette.surface))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline))
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
            query = ""
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

    private var visibleIDs: Set<UUID> {
        Set(model.history.search(query).filter(filter.matches).map(\.id))
    }
}
