import Foundation
import Observation

/// Deletes that can still be undone, for the Dictionary and Snippets pages: the same
/// behaviour as History's (`HistoryDeletion`), for any store that deletes by id.
///
/// A delete hides the items at once and only removes them when the undo window closes,
/// when another delete starts (Undo always means "the last delete"), or when `commit()` is
/// called (at quit). Until then the items are still in their store, so
/// Undo needs nothing more than forgetting them here.
@MainActor
@Observable
public final class UndoableDeletion {
    /// Deleted but still undoable. Lists should hide these, and the pipeline ignore them.
    public private(set) var pending: Set<UUID> = []

    @ObservationIgnored private var remove: (@MainActor (Set<UUID>) -> Void)?
    @ObservationIgnored private var commitTask: Task<Void, Never>?

    public init() {}

    public func isPending(_ id: UUID) -> Bool { pending.contains(id) }

    /// `items` without the ones waiting out the undo window, in the same order.
    public func visible<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID == UUID {
        pending.isEmpty ? items : items.filter { !pending.contains($0.id) }
    }

    /// Hides `ids` now and calls `remove` with them once `window` has passed (or on
    /// `commit()`). Anything already pending is committed first.
    public func delete(
        _ ids: Set<UUID>,
        after window: Duration,
        remove: @escaping @MainActor (Set<UUID>) -> Void
    ) {
        guard !ids.isEmpty else { return }
        commit()
        pending = ids
        self.remove = remove
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    /// Brings the last delete back.
    public func undo() {
        commitTask?.cancel()
        commitTask = nil
        remove = nil
        if !pending.isEmpty { pending = [] }
    }

    /// Removes whatever is pending right now.
    public func commit() {
        commitTask?.cancel()
        commitTask = nil
        guard !pending.isEmpty else { return }
        let ids = pending
        let remove = self.remove
        pending = []
        self.remove = nil
        remove?(ids)
    }
}
