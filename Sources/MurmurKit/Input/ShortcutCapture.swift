import Foundation

/// Turns the keys pressed while a shortcut recorder is listening into a `KeyShortcut`.
///
/// - A key pressed with any modifiers held records that chord (⌃⌥D, F5, ⌘Space). The rules
///   decide later whether it can be used.
/// - One modifier pressed and let go on its own records that modifier (Right ⌥, fn), when
///   the role allows it. Pressing a second modifier means a chord is coming, so letting them
///   go records nothing.
/// - Esc on its own cancels.
///
/// A pure state machine: the recorder feeds it from a local event monitor, tests drive it
/// directly.
public struct ShortcutCapture: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Still listening.
        case listening
        case captured(KeyShortcut)
        case cancelled
        /// A modifier pressed and let go on its own, for a role that needs a key with it.
        case needsKey(ModifierKey)
    }

    public let allowsLoneModifier: Bool

    /// Modifier keys down now.
    public private(set) var held: Set<ModifierKey> = []
    /// The one modifier pressed since all were up, while it's still the only one.
    private var lone: ModifierKey?

    public init(allowsLoneModifier: Bool) {
        self.allowsLoneModifier = allowsLoneModifier
    }

    /// Call on every modifier change with the event's full flags (device bits included).
    public mutating func modifiersChanged(flags: UInt64) -> Outcome {
        let now = Set(ModifierKey.allCases.filter { $0.isDown(in: flags) })
        let added = now.subtracting(held)
        let wasEmpty = held.isEmpty
        held = now

        if !added.isEmpty {
            lone = wasEmpty && now.count == 1 ? now.first : nil
            return .listening
        }
        guard now.isEmpty else { return .listening }
        defer { lone = nil }
        guard let key = lone else { return .listening }
        return allowsLoneModifier ? .captured(.modifier(key)) : .needsKey(key)
    }

    /// Call on every key-down (not auto-repeats). `typed` is what the key types on the
    /// current layout without modifiers, for its label.
    public mutating func keyDown(keyCode: UInt16, flags: UInt64, typed: String? = nil) -> Outcome {
        lone = nil
        let modifiers = ShortcutModifiers(eventFlags: flags)
        if keyCode == KeyCode.escape, modifiers.isEmpty { return .cancelled }
        return .captured(.keys(KeyChord(keyCode: keyCode, modifiers: modifiers, keyLabel: typed)))
    }

    /// What's held so far, for the recorder to echo: ["Right ⌥"] for one modifier, else the
    /// glyphs in menu order (["⌃", "⌥"]).
    public var heldGlyphs: [String] {
        let keys = held.sorted { $0.sortOrder < $1.sortOrder }
        if keys.count == 1, let key = keys.first { return [key.displayName] }
        var seen: [String] = []
        for key in keys where !seen.contains(key.glyph) { seen.append(key.glyph) }
        return seen
    }
}
