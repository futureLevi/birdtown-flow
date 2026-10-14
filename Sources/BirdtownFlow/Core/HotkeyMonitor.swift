import AppKit
import Carbon.HIToolbox
import Foundation
import MurmurKit

/// What holds the mic open: one modifier key (fn, Right ⌥, Left ⌘…) or a key with
/// modifiers (⌃⌥D, F5). The four classic choices are `KeyShortcut.quickPicks`; anything else
/// comes from the shortcut recorder. Values saved before custom shortcuts still load.
typealias PushToTalkKey = KeyShortcut

extension ModifierKey {
    /// The flag bit for this one physical key, left and right told apart.
    ///
    /// The familiar masks (`.maskAlternate`, `.maskCommand`…) are shared by both keys of a
    /// pair and stay set while either is held. Watching Right ⌥ through `.maskAlternate`
    /// would go wrong as soon as the left one is down too: letting go of Right ⌥ leaves
    /// the shared bit set, so we'd never see the release and dictation would carry on
    /// recording. The per-key bit clears exactly when this key comes up.
    var flag: CGEventFlags { CGEventFlags(rawValue: deviceFlag) }

    /// The device-independent flag. Only used to confirm a release we may have missed: if
    /// even the union bit is clear, the key is certainly up.
    var cgUnionFlag: CGEventFlags { CGEventFlags(rawValue: unionFlag) }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, and left-hand
    /// modifiers and Shift are part of everyday shortcuts and typing, so we let those through.
    /// Dedicated right-hand ⌥ ⌘ ⌃ are safe to consume.
    var shouldConsumeEvent: Bool { isRightSide && family != .shift }
}

/// Watches the push-to-talk key (or chord), plus the keys that matter while it's held, using a
/// `CGEventTap`.
///
/// Why a tap and not an `NSEvent` global monitor: a monitor only gets a copy of each event
/// after the fact, and dictation needs to take some keys away from the frontmost app (Space
/// for hands-free, Esc to cancel, a chord's own key, a right-hand modifier). The tap sees
/// the raw flags too, `fn` and the per-side modifier bits included. Creating it takes the
/// Accessibility grant, and fails without it.
///
/// The monitor only reports raw gestures; `DictationController` decides what they mean. The
/// callback runs for every keystroke on the system, so it does no work beyond a few compares
/// unless the push-to-talk key is involved.
///
/// A modifier key is held and released through flags-changed events. A chord (⌃⌥D, F5) is
/// held from its key-down with exactly its modifiers until that key comes up; both events are
/// swallowed so the key never types, and the modifiers may be let go first.
@MainActor
final class HotkeyMonitor {
    enum Event {
        /// The push-to-talk key (or chord) went down.
        case keyDown
        /// The push-to-talk key (or the chord's key) came up.
        case keyUp
        /// Another key or modifier was pressed while the push-to-talk key was held: the user
        /// is typing a shortcut (fn+←, ⌥+letter), not dictating.
        case chord
        /// Space pressed while the push-to-talk key is held. Return `true` to take it.
        case space
        /// Esc pressed. Return `true` to take it (only while dictating).
        case escape
        /// The hands-free shortcut, when `watchesControlOption` is on: Control and Option
        /// pressed together and let go with nothing else in between, or a press of
        /// `handsFreeChord` when one is set.
        case controlOptionTap
    }

    /// Tags events the app posts itself (the ⌘V paste) so the tap never mistakes them for the user.
    nonisolated static let syntheticEventTag: Int64 = 0x4D52_4D52

    private static let escapeKeyCode = Int64(kVK_Escape)
    private static let spaceKeyCode = Int64(kVK_Space)
    /// All NX_DEVICE* modifier bits: both shifts, controls, options and commands.
    private static let deviceModifierMask = ModifierKey.deviceMask

    /// The installed tap and the source that delivers its events on the main run loop; both
    /// `nil` while stopped.
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private(set) var isPressed = false
    /// Device modifier bits already down when our key went down (or since reported), so only
    /// a *newly* pressed modifier counts as a chord.
    private var knownModifiers: UInt64 = 0
    /// Mouse presses counted when a click-modifying push-to-talk key went down.
    private var clicksAtPress: UInt64 = 0
    /// Keys whose key-down we swallowed; their auto-repeats and key-up are swallowed too, so
    /// the target app never sees half a keystroke.
    private var swallowed: Set<Int64> = []
    /// Polls for a release the tap couldn't see; see `checkStillHeld()`.
    private var releaseWatch: Timer?
    /// Consecutive polls that found the key up. Two in a row are needed before acting.
    private var missedReleaseReadings = 0

    /// Recognises the ⌃⌥ tap; see `ModifierPairTap`.
    private var controlOptionRecognizer = ModifierPairTap()

    var key: PushToTalkKey = .fn
    /// Report the hands-free shortcut as `.controlOptionTap`. Only on when hands-free has a
    /// shortcut of its own (`HandsFreeShortcut.controlOption`).
    var watchesControlOption = false {
        didSet { if watchesControlOption != oldValue { resetControlOption() } }
    }
    /// The recorded hands-free chord (⌃⇧Space…), swallowed and reported as
    /// `.controlOptionTap` on its key-down. `nil` listens for the ⌃⌥ tap instead.
    var handsFreeChord: KeyChord? {
        didSet { if handsFreeChord != oldValue { resetControlOption() } }
    }
    /// Receives every gesture. The return value only matters for `.space` and `.escape`.
    var handler: ((Event) -> Bool)?
    /// Called when the system disabled the tap and it couldn't be re-enabled (Accessibility
    /// was revoked). The tap has been torn down; `start()` again once permission returns.
    var onTapLost: (() -> Void)?

    /// Whether the tap exists.
    var isArmed: Bool { eventTap != nil }

    /// What the tap subscribes to. macOS sends its tap-disabled notices regardless.
    private static let watchedEvents: CGEventMask = [CGEventType.flagsChanged, .keyDown, .keyUp]
        .reduce(CGEventMask(0)) { mask, type in mask | (CGEventMask(1) << type.rawValue) }

    /// Installs the tap on the main run loop, replacing any earlier one.
    ///
    /// The tap refers to the monitor without retaining it, so whoever owns the monitor must
    /// keep it alive while the tap is installed (`DictationController` holds it for good).
    ///
    /// - Parameter logFailure: `false` when the caller (the rearm loop) logs failures itself.
    /// - Returns: `false` when macOS won't create the tap, which nearly always means the
    ///   Accessibility grant is missing.
    @discardableResult
    func start(logFailure: Bool = true) -> Bool {
        stop()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.watchedEvents,
            callback: { _, type, event, refcon in HotkeyMonitor.route(type, event, refcon) },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            if logFailure { Log.hotkey.error("tapCreate failed — Accessibility permission missing?") }
            return false
        }
        install(tap)
        Log.hotkey.info("listening for \(self.key.displayName, privacy: .public)")
        return true
    }

    /// Removes the tap and forgets everything about the current press.
    func stop() {
        removeTap()
        stopReleaseWatch()
        isPressed = false
        knownModifiers = 0
        swallowed.removeAll()
        resetControlOption()
    }

    private func install(_ tap: CFMachPort) {
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
    }

    private func removeTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
    }

    // MARK: - Events

    /// The tap's C callback lands here, on the main thread: the tap's run-loop source was
    /// added to the main run loop. Keystrokes the app posts itself go straight through.
    private nonisolated static func route(
        _ type: CGEventType,
        _ event: CGEvent,
        _ refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        let unchanged = Unmanaged.passUnretained(event)
        guard let refcon, event.getIntegerValueField(.eventSourceUserData) != syntheticEventTag else {
            return unchanged
        }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        // The main actor gets plain values; a CGEvent isn't Sendable.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let flags = event.flags
        let swallow = MainActor.assumeIsolated {
            monitor.handle(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        }
        return swallow ? nil : unchanged
    }

    /// Whether to swallow the event: `true` keeps it from every app behind the tap.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reviveTap()
            return false
        case .flagsChanged:
            return modifiersChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            return keyDown(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        case .keyUp:
            if isPressed, let chord = key.chord, keyCode == Int64(chord.keyCode) {
                isPressed = false
                stopReleaseWatch()
                _ = handler?(.keyUp)
                return true
            }
            return swallowed.remove(keyCode) != nil
        default:
            return false
        }
    }

    /// macOS switches a tap off when its callback runs too long, and sometimes in response to
    /// what the user is doing. Turn it straight back on, and since any key could have gone up
    /// unseen in the meantime, check the real key state. If it won't come back on, the
    /// Accessibility grant has most likely been taken away: tell the owner.
    private func reviveTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        resyncAfterGap()
        guard !CGEvent.tapIsEnabled(tap: tap) else {
            Log.hotkey.notice("event tap re-enabled")
            return
        }
        Log.hotkey.error("event tap couldn't be re-enabled — Accessibility revoked?")
        // This is the tap's own callback, so leave the teardown to the next turn, and skip it
        // if a restart has installed a different tap by then.
        Task { @MainActor [weak self] in
            guard let self, self.eventTap === tap else { return }
            self.stop()
            self.onTapLost?()
        }
    }

    private func modifiersChanged(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let consume = pushToTalkModifiersChanged(keyCode: keyCode, flags: flags)
        // After the push-to-talk key has had its say: when that key is ⌃ or ⌥ itself, its
        // release has already dropped the short hold before a ⌃⌥ tap starts hands-free.
        if watchesControlOption, handsFreeChord == nil { trackControlOption(flags: flags) }
        return consume
    }

    private func pushToTalkModifiersChanged(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let ownFlag = key.modifierKey?.deviceFlag ?? 0
        let held = flags.rawValue & Self.deviceModifierMask & ~ownFlag

        if let modifier = key.modifierKey, keyCode == Int64(modifier.keyCode) {
            let nowPressed = flags.contains(modifier.flag)
            if nowPressed != isPressed {
                isPressed = nowPressed
                knownModifiers = held
                // ⌘-click, ⇧-click and ⌥-drag are shortcuts too, though no key event says so.
                // fn and the dedicated right-hand keys don't modify clicks, so a click while
                // holding them stays part of dictating.
                let modifiesClicks = modifier != .function && !modifier.shouldConsumeEvent
                if nowPressed {
                    if modifiesClicks { clicksAtPress = Self.clickCount() }
                    startReleaseWatch()
                } else {
                    stopReleaseWatch()
                    if modifiesClicks, Self.clickCount() != clicksAtPress { _ = handler?(.chord) }
                }
                _ = handler?(nowPressed ? .keyDown : .keyUp)
            }
            return modifier.shouldConsumeEvent
        }

        // Another modifier while ours is held: fn+⌘, Right ⌥+⇧… a shortcut, not dictation. A
        // chord's own modifiers were known when it went down, and letting them go is fine.
        if isPressed {
            if held & ~knownModifiers != 0 { _ = handler?(.chord) }
            knownModifiers = held
        }
        return false
    }

    private func keyDown(keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        let code = UInt16(truncatingIfNeeded: keyCode)
        if watchesControlOption {
            if let chord = handsFreeChord {
                if chord.matches(keyCode: code, eventFlags: flags.rawValue) {
                    // Taken whole, auto-repeats too, so the key never types.
                    if !isRepeat { _ = handler?(.controlOptionTap) }
                    swallowed.insert(keyCode)
                    return true
                }
            } else {
                controlOptionRecognizer.keyDown(pairHeld: flags.contains(.maskControl) || flags.contains(.maskAlternate))
            }
        }

        if let chord = key.chord, code == chord.keyCode {
            // Its auto-repeats while held never reach the app.
            if isPressed { return true }
            if !isRepeat, chord.matches(keyCode: code, eventFlags: flags.rawValue) {
                swallowed.remove(keyCode)
                isPressed = true
                knownModifiers = flags.rawValue & Self.deviceModifierMask
                startReleaseWatch()
                _ = handler?(.keyDown)
                return true
            }
        }

        if swallowed.contains(keyCode) {
            if isRepeat { return true }
            // A fresh press of a key we swallowed earlier: its key-up was lost (tap off, secure
            // input). Never let a stale entry eat the user's typing.
            swallowed.remove(keyCode)
        }

        if keyCode == Self.escapeKeyCode, handler?(.escape) == true {
            swallowed.insert(keyCode)
            return true
        }

        guard isPressed else { return false }

        if keyCode == Self.spaceKeyCode, !isRepeat, handler?(.space) == true {
            swallowed.insert(keyCode)
            return true
        }

        _ = handler?(.chord)
        return false
    }

    // MARK: - ⌃⌥ tap

    private func trackControlOption(flags: CGEventFlags) {
        let keys = ModifierPairTap.Modifiers(
            first: flags.contains(.maskControl),
            second: flags.contains(.maskAlternate),
            others: flags.contains(.maskCommand) || flags.contains(.maskShift) || flags.contains(.maskSecondaryFn)
        )
        if controlOptionRecognizer.modifiersChanged(keys, at: ProcessInfo.processInfo.systemUptime, clicks: Self.clickCount()) {
            _ = handler?(.controlOptionTap)
        }
    }

    private func resetControlOption() {
        let held = CGEventSource.flagsState(.combinedSessionState)
        controlOptionRecognizer.reset(pairHeld: held.contains(.maskControl) || held.contains(.maskAlternate))
    }

    /// Mouse presses since login, from the window server's counters. Comparing two readings
    /// tells whether a click happened in between without tapping mouse events.
    private static func clickCount() -> UInt64 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(0) { total, type in
            total + UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: type))
        }
    }

    /// After the tap was off, the key may have been released unseen. If even the union flag
    /// is clear now, report the release so nothing stays stuck "held".
    private func resyncAfterGap() {
        swallowed.removeAll()
        resetControlOption()
        guard isPressed else { return }
        if !isKeyStillDown {
            isPressed = false
            stopReleaseWatch()
            _ = handler?(.keyUp)
        }
    }

    /// What the window server says about the push-to-talk key right now, for releases the tap
    /// may have missed. A modifier is checked by its union flag, a chord by its key.
    private var isKeyStillDown: Bool {
        switch key {
        case .modifier(let modifier):
            CGEventSource.flagsState(.combinedSessionState).contains(modifier.cgUnionFlag)
        case .keys(let chord):
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(chord.keyCode))
        }
    }

    // MARK: - Missed releases under Secure Event Input

    private func startReleaseWatch() {
        stopReleaseWatch()
        // Scheduled on the main run loop, so the block provably runs on the main thread.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStillHeld() }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseWatch = timer
    }

    private func stopReleaseWatch() {
        releaseWatch?.invalidate()
        releaseWatch = nil
        missedReleaseReadings = 0
    }

    /// When focus lands in a password field mid-hold, macOS turns on Secure Event Input,
    /// which hides every key event from taps — our key's release included — without
    /// disabling the tap, so `resyncAfterGap` never runs and the microphone would stay open
    /// until the next press. Only while secure input is on, poll the modifier state instead.
    /// Gated on secure input so a quirk in the polled state can never cut a normal dictation
    /// short, and two consecutive readings are required before acting.
    private func checkStillHeld() {
        guard isPressed else {
            stopReleaseWatch()
            return
        }
        guard IsSecureEventInputEnabled() else {
            missedReleaseReadings = 0
            return
        }
        if isKeyStillDown {
            missedReleaseReadings = 0
            return
        }
        missedReleaseReadings += 1
        guard missedReleaseReadings >= 2 else { return }
        Log.hotkey.notice("release missed under secure input; resyncing")
        isPressed = false
        stopReleaseWatch()
        _ = handler?(.keyUp)
    }
}
