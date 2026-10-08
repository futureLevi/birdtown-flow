import Foundation
import Testing
@testable import MurmurKit

@Suite("HistoryDeletion")
@MainActor
struct HistoryDeletionTests {
    private func makeStore(_ texts: [String]) -> HistoryStore {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        return HistoryStore(previewRecords: texts.enumerated().map { index, text in
            HistoryRecord(createdAt: now.addingTimeInterval(-Double(index)), finalText: text)
        })
    }

    @Test("A delete hides records until it's committed, and Undo brings them back")
    func hideUndoCommit() {
        let store = makeStore(["a", "b", "c"])
        let deletion = HistoryDeletion(store: store, undoWindow: .seconds(60))
        let b = store.records[1].id

        deletion.delete([b])
        #expect(deletion.isPending(b))
        #expect(deletion.visible(store.records).map(\.finalText) == ["a", "c"])
        #expect(store.records.count == 3)

        deletion.undo()
        #expect(deletion.pending.isEmpty)
        #expect(deletion.visible(store.records).map(\.finalText) == ["a", "b", "c"])

        deletion.delete([b])
        deletion.commit()
        #expect(deletion.pending.isEmpty)
        #expect(store.records.map(\.finalText) == ["a", "c"])
    }

    @Test("A second delete commits the first, so Undo means the last delete")
    func secondDeleteCommitsFirst() {
        let store = makeStore(["a", "b", "c"])
        let deletion = HistoryDeletion(store: store, undoWindow: .seconds(60))
        let (a, b) = (store.records[0].id, store.records[1].id)

        deletion.delete([a])
        deletion.delete([b])
        #expect(store.records.map(\.finalText) == ["b", "c"])
        deletion.undo()
        #expect(store.records.map(\.finalText) == ["b", "c"])
    }

    @Test("Unknown ids are ignored")
    func unknownIDs() {
        let store = makeStore(["a"])
        let deletion = HistoryDeletion(store: store, undoWindow: .seconds(60))
        deletion.delete([UUID()])
        #expect(deletion.pending.isEmpty)
    }

    @Test("The undo window commits on its own")
    func commitsAfterWindow() async throws {
        let store = makeStore(["a", "b"])
        let deletion = HistoryDeletion(store: store, undoWindow: .milliseconds(20))
        deletion.delete([store.records[0].id])
        for _ in 0..<100 where !deletion.pending.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(deletion.pending.isEmpty)
        #expect(store.records.map(\.finalText) == ["b"])
    }
}

@Suite("ListSelection")
struct ListSelectionTests {
    let order = [1, 2, 3, 4, 5]

    @Test("Click, ⌘-click and ⇧-click")
    func clicks() {
        var selection = ListSelection<Int>()
        selection.click(2, .plain, in: order)
        #expect(selection.ids == [2])
        selection.click(4, .toggle, in: order)
        #expect(selection.ids == [2, 4])
        selection.click(4, .toggle, in: order)
        #expect(selection.ids == [2])
        selection.click(2, .plain, in: order)
        selection.click(5, .extend, in: order)
        #expect(selection.ids == [2, 3, 4, 5])
        // The anchor stays put: ⇧-clicking above it flips the range.
        selection.click(1, .extend, in: order)
        #expect(selection.ids == [1, 2])
        #expect(selection.ordered(in: order) == [1, 2])
    }

    @Test("⇧-click with nothing selected selects just that row")
    func extendWithoutAnchor() {
        var selection = ListSelection<Int>()
        selection.click(3, .extend, in: order)
        #expect(selection.ids == [3])
    }

    @Test("Arrow keys move, clamp at the ends, and start from the top or bottom")
    func arrows() {
        var selection = ListSelection<Int>()
        #expect(selection.move(1, in: order) == 1)
        #expect(selection.move(-1, in: order) == 1)
        #expect(selection.ids == [1])
        selection.move(1, in: order)
        selection.move(1, in: order)
        #expect(selection.ids == [3])

        var fromBottom = ListSelection<Int>()
        #expect(fromBottom.move(-1, in: order) == 5)
        #expect(fromBottom.move(1, in: order) == 5)

        var empty = ListSelection<Int>()
        #expect(empty.move(1, in: []) == nil)
    }

    @Test("⇧-arrows grow and shrink the range from the anchor")
    func shiftArrows() {
        var selection = ListSelection<Int>()
        selection.click(3, .plain, in: order)
        selection.move(1, in: order, extending: true)
        selection.move(1, in: order, extending: true)
        #expect(selection.ids == [3, 4, 5])
        selection.move(-1, in: order, extending: true)
        #expect(selection.ids == [3, 4])
        selection.move(-1, in: order, extending: true)
        selection.move(-1, in: order, extending: true)
        #expect(selection.ids == [2, 3])
    }

    @Test("Select All, single, prune and remove")
    func bulk() {
        var selection = ListSelection<Int>()
        selection.selectAll(order)
        #expect(selection.count == 5)
        #expect(selection.single(in: order) == nil)
        selection.prune(to: [2, 3])
        #expect(selection.ids == [2, 3])
        selection.remove([2])
        #expect(selection.single(in: order) == 3)
        #expect(selection.single(in: [1]) == nil)
        selection.clear()
        #expect(selection.isEmpty)
    }
}

@Suite("SearchHighlight")
struct SearchHighlightTests {
    @Test("Finds every match, ignoring case and accents")
    func ranges() {
        let text = "Café notes: the CAFE opens at nine, cafe closes at five."
        let found = SearchHighlight.ranges(of: " cafe ", in: text).map { String(text[$0]) }
        #expect(found == ["Café", "CAFE", "cafe"])
        #expect(SearchHighlight.ranges(of: "  ", in: text).isEmpty)
        #expect(SearchHighlight.ranges(of: "tea", in: text).isEmpty)
    }

    @Test("Says which fields matched")
    func fields() {
        let record = HistoryRecord(
            context: AppContext(bundleID: nil, appName: "Slack", category: .work),
            rawText: "um the migration plan", finalText: "The migration plan.")
        #expect(SearchHighlight.fields(of: record, matching: "migration") == [.text, .heard])
        #expect(SearchHighlight.fields(of: record, matching: "slack") == [.app])
        #expect(SearchHighlight.fields(of: record, matching: "um the") == [.heard])
        #expect(SearchHighlight.fields(of: record, matching: "") == [])
    }

    @Test("A match past the preview gets an excerpt that starts at a word")
    func excerpt() {
        let text = String(repeating: "word ", count: 60) + "the migration plan is ready"
        let preview = SearchHighlight.preview(of: text, query: "migration", budget: 100, lead: 12)
        #expect(preview.isExcerpt)
        #expect(preview.text.hasPrefix("…"))
        #expect(!preview.text.hasPrefix("… "))
        #expect(preview.text.hasSuffix("the migration plan is ready"))
        #expect(preview.ranges.map { String(preview.text[$0]) } == ["migration"])
        // Each word in the excerpt is whole.
        #expect(preview.text.dropFirst().split(separator: " ").allSatisfy { ["word", "the", "migration", "plan", "is", "ready"].contains(String($0)) })
    }

    @Test("A match inside the preview keeps the whole text")
    func noExcerpt() {
        let text = "The migration plan is ready. " + String(repeating: "word ", count: 60)
        let preview = SearchHighlight.preview(of: text, query: "migration", budget: 100)
        #expect(!preview.isExcerpt)
        #expect(preview.text == text)
        #expect(preview.ranges.count == 1)
        #expect(SearchHighlight.preview(of: text, query: "", budget: 100).ranges.isEmpty)
    }
}

@Suite("Retranscription")
struct RetranscriptionTests {
    let good = HistoryRecord(finalText: "Ship it on Friday.", outcome: .inserted)

    @Test("Retrying a failed dictation takes the new result")
    func failedRecord() {
        let failed = HistoryRecord(outcome: .failed, errorMessage: "Model not loaded")
        let result = HistoryRecord(outcome: .failed, errorMessage: "Still not loaded")
        #expect(Retranscription.resolve(previous: failed, result: result) == .updated)
    }

    @Test("New text replaces good text, and the old text is kept for restoring")
    func replaced() {
        let result = HistoryRecord(id: good.id, finalText: "Ship it Friday.", outcome: .copied)
        #expect(Retranscription.resolve(previous: good, result: result) == .replaced(previous: good))
    }

    @Test("An error or silence never costs good text")
    func kept() {
        let failed = HistoryRecord(id: good.id, outcome: .failed, errorMessage: "Engine crashed")
        #expect(Retranscription.resolve(previous: good, result: failed)
            == .keptPrevious(previous: good, reason: "Engine crashed"))
        let empty = HistoryRecord(id: good.id, outcome: .empty)
        #expect(Retranscription.resolve(previous: good, result: empty)
            == .keptPrevious(previous: good, reason: "No speech was heard this time."))
        let blank = HistoryRecord(id: good.id, finalText: "  ", outcome: .copied)
        #expect(Retranscription.resolve(previous: good, result: blank)
            == .keptPrevious(previous: good, reason: "No speech was heard this time."))
    }
}
