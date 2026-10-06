import AppKit
import Carbon.HIToolbox
import Foundation

/// Which modifier key holds the mic open.
enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption
    case fn
    case rightCommand
    case rightControl

    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)   // 61
        case .fn: Int64(kVK_Function)               // 63
        case .rightCommand: Int64(kVK_RightCommand) // 54
        case .rightControl: Int64(kVK_RightControl) // 62
        }
    }

    /// Device-*dependent* bit for this specific physical key.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — it's set whenever *either* Option
    /// key is down. Using it means: hold Left ⌥, tap Right ⌥, and the release is invisible
    /// (the union bit is still set by the left key), so `onRelease` never fires. The mic
    /// stays open, the HUD stays up, and the next press is swallowed too.
    ///
    /// These raw values are the NX_DEVICE* masks from IOKit's event system; they carry the
    /// left/right distinction that the public `CGEventFlags` constants discard.
    var flag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)    // NX_DEVICERALTKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x10)   // NX_DEVICERCMDKEYMASK
        case .rightControl: CGEventFlags(rawValue: 0x2000) // NX_DEVICERCTLKEYMASK
        case .fn: .maskSecondaryFn                         // no left/right variant exists
        }
    }

    /// The device-independent flag. Only used to confirm a release we may have missed: if
    /// even the union bit is clear, the key is certainly up.
    var unionFlag: CGEventFlags {
        switch self {
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        case .rightControl: .maskControl
        case .fn: .maskSecondaryFn
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .fn: "fn"
        case .rightCommand: "Right ⌘"
        case .rightControl: "Right ⌃"
        }
    }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, so we let it
    /// through. Dedicated right-hand modifiers are safe to consume.
    var shouldConsumeEvent: Bool { self != .fn }
}

/// Watches the push-to-talk key, plus the keys that matter while it's held, using a `CGEventTap`.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` because `fn` and left/right
/// modifier discrimination don't surface through the higher-level APIs, and because Space
/// (hands-free) and Esc (cancel) must be *swallowed* while dictating. This needs
/// Accessibility permission; without it `CGEvent.tapCreate` returns nil.
///
/// The monitor only reports raw gestures; `DictationController` decides what they mean. The
/// callback runs for every keystroke on the system, so it does no work beyond a few compares
/// unless the push-to-talk key is involved.
@MainActor
final class HotkeyMonitor {
    enum Event {
        /// The push-to-talk key went down.
        case keyDown
        /// The push-to-talk key came up.
        case keyUp
        /// Another key or modifier was pressed while the push-to-talk key was held: the user
        /// is typing a shortcut (fn+←, ⌥+letter), not dictating.
        case chord
        /// Space pressed while the push-to-talk key is held. Return `true` to take it.
        case space
        /// Esc pressed. Return `true` to take it (only while dictating).
        case escape
    }

    /// Tags events the app posts itself (the ⌘V paste) so the tap never mistakes them for the user.
    nonisolated static let syntheticEventTag: Int64 = 0x4D52_4D52

    private static let escapeKeyCode = Int64(kVK_Escape)
    private static let spaceKeyCode = Int64(kVK_Space)
    /// All NX_DEVICE* modifier bits: both shifts, controls, options and commands.
    private static let deviceModifierMask: UInt64 = 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x2000

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isPressed = false
    /// Device modifier bits already down when our key went down (or since reported), so only
    /// a *newly* pressed modifier counts as a chord.
    private var knownModifiers: UInt64 = 0
    /// Keys whose key-down we swallowed; their auto-repeats and key-up are swallowed too, so
    /// the target app never sees half a keystroke.
    private var swallowed: Set<Int64> = []
    /// Polls for a release the tap couldn't see; see `checkStillHeld()`.
    private var releaseWatch: Timer?
    /// Consecutive polls that found the key up. Two in a row are needed before acting.
    private var missedReleaseReadings = 0

    var key: PushToTalkKey = .fn
    /// Receives every gesture. The return value only matters for `.space` and `.escape`.
    var handler: ((Event) -> Bool)?
    /// Called when the system disabled the tap and it couldn't be re-enabled (Accessibility
    /// was revoked). The tap has been torn down; `start()` again once permission returns.
    var onTapLost: (() -> Void)?

    /// Whether the tap exists.
    var isArmed: Bool { tap != nil }

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                if event.getIntegerValueField(.eventSourceUserData) == HotkeyMonitor.syntheticEventTag {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.key.displayName, privacy: .public)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        stopReleaseWatch()
        isPressed = false
        knownModifiers = 0
        swallowed.removeAll()
    }

    // MARK: - Tap callback

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system disables a tap that runs too slowly or is interrupted; re-arm it,
            // and assume we may have missed a release while it was off.
            guard let tap else { return false }
            CGEvent.tapEnable(tap: tap, enable: true)
            resyncAfterGap()
            if CGEvent.tapIsEnabled(tap: tap) {
                Log.hotkey.notice("event tap re-enabled")
            } else {
                Log.hotkey.error("event tap couldn't be re-enabled — Accessibility revoked?")
                // Not from inside the tap's own callback: tear down on the next turn.
                Task { @MainActor [weak self] in
                    guard let self, self.tap === tap else { return }
                    self.stop()
                    self.onTapLost?()
                }
            }
            return false
        case .flagsChanged:
            return modifiersChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            return keyDown(keyCode: keyCode, isRepeat: isRepeat)
        case .keyUp:
            return swallowed.remove(keyCode) != nil
        default:
            return false
        }
    }

    private func modifiersChanged(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let held = flags.rawValue & Self.deviceModifierMask & ~key.flag.rawValue

        if keyCode == key.keyCode {
            let nowPressed = flags.contains(key.flag)
            if nowPressed != isPressed {
                isPressed = nowPressed
                knownModifiers = held
                if nowPressed { startReleaseWatch() } else { stopReleaseWatch() }
                _ = handler?(nowPressed ? .keyDown : .keyUp)
            }
            return key.shouldConsumeEvent
        }

        // Another modifier while ours is held: fn+⌘, Right ⌥+⇧… a shortcut, not dictation.
        if isPressed {
            if held & ~knownModifiers != 0 { _ = handler?(.chord) }
            knownModifiers = held
        }
        return false
    }

    private func keyDown(keyCode: Int64, isRepeat: Bool) -> Bool {
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

    /// After the tap was off, the key may have been released unseen. If even the union flag
    /// is clear now, report the release so nothing stays stuck "held".
    private func resyncAfterGap() {
        swallowed.removeAll()
        guard isPressed else { return }
        if !CGEventSource.flagsState(.combinedSessionState).contains(key.unionFlag) {
            isPressed = false
            stopReleaseWatch()
            _ = handler?(.keyUp)
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
        if CGEventSource.flagsState(.combinedSessionState).contains(key.unionFlag) {
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
