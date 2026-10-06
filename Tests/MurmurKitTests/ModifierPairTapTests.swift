import Testing
@testable import MurmurKit

@Suite("ModifierPairTap")
struct ModifierPairTapTests {
    typealias Keys = ModifierPairTap.Modifiers
    static let none = Keys(first: false, second: false)
    static let ctrl = Keys(first: true, second: false)
    static let opt = Keys(first: false, second: true)
    static let both = Keys(first: true, second: true)

    /// Feeds modifier states at the given times and returns how many taps fired.
    private func taps(_ tap: inout ModifierPairTap, _ steps: [(Keys, Double)], clicks: UInt64 = 0) -> Int {
        steps.reduce(0) { count, step in
            count + (tap.modifiersChanged(step.0, at: step.1, clicks: clicks) ? 1 : 0)
        }
    }

    @Test("A clean tap fires once, on the release")
    func cleanTap() {
        var tap = ModifierPairTap()
        let pressed = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05)])
        let armed = tap.isArmed
        let released = taps(&tap, [(Self.ctrl, 0.2)])
        let afterwards = taps(&tap, [(Self.none, 0.25)])
        #expect(pressed == 0)
        #expect(armed)
        #expect(released == 1)
        #expect(afterwards == 0)
    }

    @Test("Either key can come up first, and either can go down first")
    func releaseOrder() {
        var tap = ModifierPairTap()
        let optionFirst = taps(&tap, [(Self.opt, 0), (Self.both, 0.04), (Self.opt, 0.2), (Self.none, 0.22)])
        let controlFirst = taps(&tap, [(Self.ctrl, 1), (Self.both, 1.04), (Self.ctrl, 1.2), (Self.none, 1.22)])
        #expect(optionFirst == 1)
        #expect(controlFirst == 1)
    }

    @Test("Two taps in a row both fire: start, then finish")
    func twoTaps() {
        var tap = ModifierPairTap()
        let first = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05), (Self.none, 0.2)])
        let second = taps(&tap, [(Self.opt, 3), (Self.both, 3.05), (Self.ctrl, 3.2), (Self.none, 3.25)])
        #expect(first == 1)
        #expect(second == 1)
    }

    @Test("A key pressed with them is a shortcut (⌃⌥V), not a tap")
    func shortcutKey() {
        var tap = ModifierPairTap()
        _ = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05)])
        tap.keyDown(pairHeld: true)
        let shortcut = taps(&tap, [(Self.ctrl, 0.3), (Self.none, 0.35)])
        // And the next clean tap still works.
        let next = taps(&tap, [(Self.ctrl, 1), (Self.both, 1.05), (Self.none, 1.2)])
        #expect(shortcut == 0)
        #expect(next == 1)
    }

    @Test("A key typed with one of them held spoils the pair, even if the other joins later")
    func typedWithOneHeld() {
        var tap = ModifierPairTap()
        _ = taps(&tap, [(Self.opt, 0)])
        tap.keyDown(pairHeld: true)  // ⌥ + a letter
        let count = taps(&tap, [(Self.both, 0.3), (Self.opt, 0.4), (Self.none, 0.5)])
        #expect(count == 0)
    }

    @Test("Keys typed with neither held don't matter")
    func unrelatedTyping() {
        var tap = ModifierPairTap()
        tap.keyDown(pairHeld: false)
        let count = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05), (Self.none, 0.2)])
        #expect(count == 1)
    }

    @Test("Another modifier with them (⌘⌃⌥) is not a tap")
    func extraModifier() {
        var tap = ModifierPairTap()
        let withCommand = Keys(first: true, second: true, others: true)
        let joined = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05), (withCommand, 0.1), (Self.both, 0.15), (Self.none, 0.2)])
        // Held before them, too.
        let commandOnly = Keys(first: false, second: false, others: true)
        let commandCtrl = Keys(first: true, second: false, others: true)
        let first = taps(&tap, [(commandOnly, 1), (commandCtrl, 1.05), (withCommand, 1.1), (Self.ctrl, 1.2), (Self.none, 1.3)])
        #expect(joined == 0)
        #expect(first == 0)
    }

    @Test("Held too long, it was an abandoned shortcut")
    func longHold() {
        var tap = ModifierPairTap(maxHold: 1.2)
        let count = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05), (Self.none, 2)])
        #expect(count == 0)
    }

    @Test("A click while they're down is ⌃⌥-click, not a tap")
    func click() {
        var tap = ModifierPairTap()
        _ = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05)], clicks: 10)
        let count = taps(&tap, [(Self.ctrl, 0.3)], clicks: 11)
        #expect(count == 0)
    }

    @Test("After a tap with one key still down, a new tap waits for both to come up")
    func lingeringKey() {
        var tap = ModifierPairTap()
        let first = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05), (Self.ctrl, 0.2)])
        // ⌥ goes down again while ⌃ never came up: not a fresh tap.
        let again = taps(&tap, [(Self.both, 0.4), (Self.ctrl, 0.5), (Self.none, 0.6)])
        #expect(first == 1)
        #expect(again == 0)
    }

    @Test("A reset while held waits for release; a reset with nothing held is ready at once")
    func reset() {
        var tap = ModifierPairTap()
        _ = taps(&tap, [(Self.ctrl, 0), (Self.both, 0.05)])
        tap.reset(pairHeld: true)
        let armed = tap.isArmed
        let stale = taps(&tap, [(Self.ctrl, 0.2), (Self.none, 0.3)])
        tap.reset(pairHeld: false)
        let fresh = taps(&tap, [(Self.opt, 1), (Self.both, 1.05), (Self.none, 1.2)])
        #expect(!armed)
        #expect(stale == 0)
        #expect(fresh == 1)
    }
}
