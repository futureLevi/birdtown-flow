import Foundation
import Observation

/// Deletes from History that can still be undone.
///
/// A delete hides the records at once and only removes them (and their audio) from the
/// store when the undo window closes, when another delete starts, or when `commit()` is
/// called (on quit). It lives on the app model rather than in a page, so a delete made on
/// Home or History survives switching pages and the same Undo works from either.
@MainActor
@Observable
public final class HistoryDeletion {
    /// Deleted but still undoable. Lists should hide these.
    public private(set) var pending: Set<UUID> = []

    private let store: HistoryStore
    private let undoWindow: Duration
    @ObservationIgnored private var commitTask: Task<Void, Never>?

    public init(store: HistoryStore, undoWindow: Duration = .seconds(5)) {
        self.store = store
        self.undoWindow = undoWindow
    }

    public func isPending(_ id: UUID) -> Bool { pending.contains(id) }

    /// What lists leave out: deletes waiting out the undo window, and the rows of recordings
    /// still in progress (`HistoryStore.inProgress`).
    public var hidden: Set<UUID> {
        let inProgress = store.inProgress
        return inProgress.isEmpty ? pending : pending.union(inProgress)
    }

    public func isHidden(_ id: UUID) -> Bool {
        pending.contains(id) || store.inProgress.contains(id)
    }

    /// `records` without the hidden ones, in the same order.
    public func visible(_ records: [HistoryRecord]) -> [HistoryRecord] {
        let hidden = self.hidden
        return hidden.isEmpty ? records : records.filter { !hidden.contains($0.id) }
    }

    /// Hides `ids` now and removes them for good once the undo window closes. Anything
    /// already pending is committed first: Undo always means "the last delete".
    /// `window` overrides the undo window for this delete (snapshots hold one open).
    public func delete(_ ids: Set<UUID>, window: Duration? = nil) {
        commit()
        let ids = ids.filter { store.record(id: $0) != nil }
        guard !ids.isEmpty else { return }
        pending = ids
        let duration = window ?? undoWindow
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    /// Brings the last delete back.
    public func undo() {
        commitTask?.cancel()
        commitTask = nil
        pending = []
    }

    /// Removes whatever is pending right now.
    public func commit() {
        commitTask?.cancel()
        commitTask = nil
        guard !pending.isEmpty else { return }
        let ids = pending
        pending = []
        store.delete(ids: ids)
    }
}
