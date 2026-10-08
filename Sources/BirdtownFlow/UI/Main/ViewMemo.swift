/// Remembers the last value worked out from a key, so a view's body can skip derived work
/// (searching, grouping, counting) when what it depends on hasn't changed.
///
/// Hold it in `@State`: it's a plain reference, not observed, so filling it from `body` never
/// invalidates the view. Keys holding `[HistoryRecord]` compare cheaply when nothing changed,
/// because an unmodified array still shares its storage and `==` checks that first.
@MainActor
final class ViewMemo<Key: Equatable, Value> {
    private var cached: (key: Key, value: Value)?

    func value(for key: Key, _ compute: (Key) -> Value) -> Value {
        if let hit = cached, hit.key == key { return hit.value }
        let value = compute(key)
        cached = (key, value)
        return value
    }
}
