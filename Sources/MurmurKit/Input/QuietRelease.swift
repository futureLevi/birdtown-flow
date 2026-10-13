import Foundation

/// Holds objects that are finished with but mustn't be freed yet, and hands each one back once
/// it has gone `quietPeriod` without activity.
///
/// For `AudioRecorder`'s retired `AVAudioEngine`s: AVFAudio queues property-listener blocks for
/// an engine's input unit on its own dispatch queue, and freeing the engine while one of those
/// is still waiting crashes in Apple's code when the block runs. Hardware changes come in bursts,
/// so a replaced engine is held here, its quiet period restarting on every configuration change
/// it reports, and freed once it has been quiet for a while.
///
/// A pure value with caller-supplied times, so tests drive it with plain numbers.
public struct QuietRelease<Key: Hashable, Item> {
    /// How long an item must go without `noteActivity` before `takeQuiet` releases it.
    public let quietPeriod: TimeInterval

    private var held: [Key: (item: Item, lastActivity: TimeInterval)] = [:]

    public init(quietPeriod: TimeInterval) {
        self.quietPeriod = quietPeriod
    }

    public var count: Int { held.count }
    public var isEmpty: Bool { held.isEmpty }

    /// Starts holding `item`. Its quiet period starts now. Retiring a key that's already held
    /// replaces that item and restarts the period.
    public mutating func retire(_ item: Item, key: Key, at now: TimeInterval) {
        held[key] = (item, now)
    }

    /// Restarts the quiet period of the item held under `key`.
    /// - Returns: `false` when nothing is held under `key`.
    @discardableResult
    public mutating func noteActivity(key: Key, at now: TimeInterval) -> Bool {
        guard var entry = held[key] else { return false }
        entry.lastActivity = max(entry.lastActivity, now)
        held[key] = entry
        return true
    }

    public func isHolding(_ key: Key) -> Bool { held[key] != nil }

    /// Stops holding, and returns, every item that has been quiet for at least `quietPeriod`.
    public mutating func takeQuiet(at now: TimeInterval) -> [Item] {
        let due = held.filter { now - $0.value.lastActivity >= quietPeriod }
        for key in due.keys { held[key] = nil }
        return due.values.sorted { $0.lastActivity < $1.lastActivity }.map { $0.item }
    }

    /// When the first held item will become quiet, or `nil` when nothing is held.
    public var nextDue: TimeInterval? {
        held.values.map { $0.lastActivity + quietPeriod }.min()
    }
}

extension QuietRelease: Sendable where Key: Sendable, Item: Sendable {}
