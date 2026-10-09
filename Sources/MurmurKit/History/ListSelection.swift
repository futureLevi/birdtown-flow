import Foundation

/// Mac list selection: click, ⌘-click, ⇧-click, arrow keys (with or without ⇧) and Select All,
/// the way Finder and Mail behave. Pure state, so the History page stays a thin view.
///
/// `order` is always the list as it's shown, top to bottom. Selected ids that a search or a
/// filter hides stay in `ids` until `prune(to:)` drops them.
public struct ListSelection<ID: Hashable & Sendable>: Equatable, Sendable {
    /// How a row was clicked.
    public enum Click: Sendable {
        /// Select only this row.
        case plain
        /// ⌘: add or remove this row.
        case toggle
        /// ⇧: select from the anchor to this row.
        case extend
    }

    public private(set) var ids: Set<ID> = []
    /// Where a ⇧ range starts: the last row clicked without ⇧.
    public private(set) var anchor: ID?
    /// The row the keyboard is on: the last row clicked or moved to.
    public private(set) var cursor: ID?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }
    public func contains(_ id: ID) -> Bool { ids.contains(id) }

    /// The selected ids in list order (for copying several rows top to bottom).
    public func ordered(in order: [ID]) -> [ID] {
        order.filter { ids.contains($0) }
    }

    /// Exactly one row selected and still listed: the one Return acts on.
    public func single(in order: [ID]) -> ID? {
        guard ids.count == 1, let only = ids.first, order.contains(only) else { return nil }
        return only
    }

    public mutating func click(_ id: ID, _ kind: Click, in order: [ID]) {
        switch kind {
        case .plain:
            select(id)
        case .toggle:
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchor = id
            cursor = id
        case .extend:
            guard let anchor, let range = Self.range(from: anchor, to: id, in: order) else {
                select(id)
                return
            }
            ids = Set(order[range])
            cursor = id
        }
    }

    /// Moves the keyboard cursor `step` rows (negative is up) and returns the row it lands
    /// on, to scroll to. With nothing selected, ↓ starts at the top and ↑ at the bottom.
    /// `extending` (⇧) grows or shrinks the range from the anchor instead of replacing it.
    @discardableResult
    public mutating func move(_ step: Int, in order: [ID], extending: Bool = false) -> ID? {
        guard !order.isEmpty, step != 0 else { return nil }
        let target: ID
        if let cursor, let index = order.firstIndex(of: cursor), !ids.isEmpty {
            target = order[min(max(index + step, 0), order.count - 1)]
        } else {
            target = step > 0 ? order[0] : order[order.count - 1]
        }
        if extending, let anchor, let range = Self.range(from: anchor, to: target, in: order) {
            ids = Set(order[range])
            cursor = target
        } else {
            select(target)
        }
        return target
    }

    public mutating func selectAll(_ order: [ID]) {
        guard !order.isEmpty else { return }
        ids = Set(order)
        if anchor.map({ !order.contains($0) }) ?? true { anchor = order.first }
        if cursor.map({ !order.contains($0) }) ?? true { cursor = order.first }
    }

    /// Selects one row, as a plain click would.
    public mutating func select(_ id: ID) {
        ids = [id]
        anchor = id
        cursor = id
    }

    public mutating func clear() {
        ids = []
        anchor = nil
        cursor = nil
    }

    /// Forgets rows that are no longer listed (deleted, or hidden by a search or filter).
    public mutating func prune(to order: [ID]) {
        let listed = Set(order)
        ids.formIntersection(listed)
        if let anchor, !listed.contains(anchor) { self.anchor = nil }
        if let cursor, !listed.contains(cursor) { self.cursor = nil }
    }

    public mutating func remove(_ removed: Set<ID>) {
        ids.subtract(removed)
        if let anchor, removed.contains(anchor) { self.anchor = nil }
        if let cursor, removed.contains(cursor) { self.cursor = nil }
    }

    private static func range(from start: ID, to end: ID, in order: [ID]) -> ClosedRange<Int>? {
        guard let a = order.firstIndex(of: start), let b = order.firstIndex(of: end) else { return nil }
        return min(a, b)...max(a, b)
    }
}
