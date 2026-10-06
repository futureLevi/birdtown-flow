import Foundation

/// Recognises a tap of two modifier keys pressed together, such as ⌃⌥ for hands-free: both
/// down with nothing else held, then either one up within `maxHold`, with no key, click or
/// other modifier in between. It fires on the release, so a shortcut that starts the same way
/// (⌃⌥V, ⌃⌥←, ⌃⌥-click) is never mistaken for it.
///
/// A pure state machine: `HotkeyMonitor` feeds it from its event tap, and tests drive it
/// directly.
public struct ModifierPairTap: Sendable {
    /// Which keys are down after a modifier change.
    public struct Modifiers: Sendable, Equatable {
        public var first: Bool
        public var second: Bool
        /// Any modifier outside the pair (⌘, ⇧, fn).
        public var others: Bool

        public init(first: Bool, second: Bool, others: Bool = false) {
            self.first = first
            self.second = second
            self.others = others
        }

        var either: Bool { first || second }
        var both: Bool { first && second }
    }

    /// Held longer than this, it was a shortcut abandoned halfway, not a tap.
    public var maxHold: TimeInterval

    /// When both went down cleanly, while they still are.
    private var downAt: TimeInterval?
    /// The click counter when they went down: any click since means ⌃⌥-click.
    private var clicksAtDown: UInt64 = 0
    /// Something joined them, so this isn't a tap. Stays set until both are up again.
    private var spoiled = false

    public init(maxHold: TimeInterval = 1.2) {
        self.maxHold = maxHold
    }

    /// Whether both keys are down and could still become a tap.
    public var isArmed: Bool { downAt != nil && !spoiled }

    /// Call on every modifier change. `clicks` is any counter of mouse presses that only goes
    /// up. Returns `true` when this change completes a tap.
    public mutating func modifiersChanged(_ keys: Modifiers, at time: TimeInterval, clicks: UInt64) -> Bool {
        if let downAt {
            if keys.others { spoiled = true }
            guard !keys.both else { return false }
            self.downAt = nil
            let tapped = !spoiled && time - downAt <= maxHold && clicks == clicksAtDown
            // If one key is still down, wait for it before a new tap can begin.
            spoiled = keys.either
            return tapped
        }

        if !keys.either {
            spoiled = false
        } else if keys.both && !keys.others && !spoiled {
            downAt = time
            clicksAtDown = clicks
        } else if keys.others {
            // ⌘⌃⌥ and friends: not ours until everything is let go.
            spoiled = true
        }
        return false
    }

    /// Call on every key press. `pairHeld` is whether either key of the pair was down with it:
    /// a key typed with ⌃ or ⌥ down is a shortcut, even if the other joins afterwards.
    public mutating func keyDown(pairHeld: Bool) {
        if pairHeld { spoiled = true }
    }

    /// Forget any tap in progress, after events may have been missed. Keys still held went
    /// down before we were watching, so wait for them to come up.
    public mutating func reset(pairHeld: Bool) {
        downAt = nil
        spoiled = pairHeld
    }
}
