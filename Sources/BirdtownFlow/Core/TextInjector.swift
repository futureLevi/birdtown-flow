import AppKit
import ApplicationServices
import Carbon
import Foundation

/// Puts text into whatever field currently has keyboard focus.
///
/// Two strategies:
/// 1. **Accessibility** — set `kAXSelectedTextAttribute` on the focused element. Clean and
///    instant, and it leaves the pasteboard untouched.
/// 2. **Pasteboard + ⌘V** — works in Electron apps and anything else with a half-hearted
///    AX implementation. The previous pasteboard contents are restored afterwards.
///
/// The catch that makes this non-obvious: **many apps return `.success` from the AX write
/// and then do nothing.** Electron (Cursor, VS Code, Slack, Discord), Chrome, and most
/// terminal emulators all report `kAXSelectedTextAttribute` as settable, accept the write,
/// and silently drop it. So the return value is not evidence of anything — strategy 1 is
/// only trusted when the insertion point can be *observed* to have moved, and apps known to
/// fake it go straight to strategy 2.
///
/// This all works because the HUD is a non-activating panel: focus never leaves the user's
/// target app, so "the focused element" is still their text field.
@MainActor
enum TextInjector {
    enum Outcome: Equatable, Sendable {
        /// Typed (or pasted) into the focused field.
        case inserted
        /// Left on the clipboard instead, for the user to paste.
        case copied(CopyReason)
    }

    enum CopyReason: Equatable, Sendable {
        /// Nothing editable had focus.
        case noTextField
        /// Secure input is on (a password field, or a terminal's Secure Keyboard Entry).
        case secureInput
        /// Accessibility isn't granted, so the app can't type.
        case noAccessibility

        /// Short, human message for the HUD.
        var message: String {
            switch self {
            case .noTextField: "Copied · press ⌘V to paste"
            case .secureInput: "Password field · copied, press ⌘V"
            case .noAccessibility: "Copied · press ⌘V, or allow Accessibility"
            }
        }
    }

    /// Inserts `text` at the caret, or leaves it on the clipboard when there's nowhere to type.
    static func insert(_ text: String, restoreClipboard: Bool) async -> Outcome {
        guard !text.isEmpty else { return .inserted }
        configureMessagingTimeout()

        // Typing into a password prompt is never right, even if it would work.
        if IsSecureEventInputEnabled() {
            copy(text)
            return .copied(.secureInput)
        }
        guard AXIsProcessTrusted() else {
            copy(text)
            return .copied(.noAccessibility)
        }

        let pasteFirst = prefersPasteboard(NSWorkspace.shared.frontmostApplication)

        // Every AX call blocks until the target app answers, and the hotkey's event tap lives
        // on the main run loop, so the probe and write run on their own queue: a slow app
        // stalls this dictation, not the keyboard. The decisions are the same as on main.
        let attempt = await withCheckedContinuation { (continuation: CheckedContinuation<AXAttempt, Never>) in
            axQueue.async {
                continuation.resume(returning: attemptViaAccessibility(text, pasteFirst: pasteFirst))
            }
        }

        switch attempt {
        case .noTextField:
            copy(text)
            return .copied(.noTextField)
        case .inserted:
            return .inserted
        case .needsPaste(let spacedText):
            await paste(spacedText, restoreClipboard: restoreClipboard)
            return .inserted
        }
    }

    /// Puts `text` on the clipboard as an ordinary copy (clipboard managers keep it).
    static func copy(_ text: String) {
        cancelPendingRestore()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Smart spacing

    /// Prepends a space when the caret sits right after a word, so consecutive dictations
    /// don't run together — and never doubles one.
    nonisolated static func spaced(_ text: String, after previous: Character) -> String {
        guard let first = text.first else { return text }
        if previous.isWhitespace {
            return first == " " ? String(text.drop { $0 == " " }) : text
        }
        if first.isWhitespace { return text }
        // Punctuation attaches to the previous word; openers and joiners take no space after.
        if ",.;:!?)]}’”%…".contains(first) { return text }
        if "([{“‘\"'/\\-@#$_`".contains(previous) { return text }
        return " " + text
    }

    // MARK: - Accessibility

    /// AX calls block until the target app answers; a hung app would otherwise stall us for
    /// the default six seconds. Setting it on the system-wide element sets the process default.
    private static var didConfigureTimeout = false

    private static func configureMessagingTimeout() {
        guard !didConfigureTimeout else { return }
        didConfigureTimeout = true
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
    }

    /// What the off-main AX pass decided; the pasteboard side stays on the main actor.
    private enum AXAttempt: Sendable {
        /// Typed into the focused field via AX.
        case inserted
        /// Nothing editable had focus (only reported outside the paste-first list).
        case noTextField
        /// Paste this (already smart-spaced) text instead.
        case needsPaste(String)
    }

    /// Serial, so AX reads and writes from back-to-back dictations never interleave.
    private nonisolated static let axQueue = DispatchQueue(label: "com.birdtownlabs.flow.inject", qos: .userInitiated)

    /// The whole AX side of `insert`: find the focused field, probe for spacing, try the write.
    /// Runs on `axQueue`; the `AXUIElement` never leaves it.
    private nonisolated static func attemptViaAccessibility(_ text: String, pasteFirst: Bool) -> AXAttempt {
        let focused = focusedElement()

        // Apps on the paste-first list often build their AX tree lazily, so "nothing focused"
        // there means nothing. Everywhere else it's trustworthy.
        if !pasteFirst {
            guard let focused, isTextInput(focused) else { return .noTextField }
        }

        // Read once: it feeds the spacing probe and is the "before" of the AX write's movement
        // check. Only reads happen in between, so a second read would return the same range.
        let range = focused.flatMap { selectedRange(of: $0) }

        var text = text
        if let focused, let range, let previous = characterBeforeCaret(in: focused, at: range) {
            text = spaced(text, after: previous)
        }

        if !pasteFirst, let focused, insertViaAccessibility(text, into: focused, before: range) {
            Log.inject.info("inserted via AX (\(text.count) chars)")
            return .inserted
        }
        return .needsPaste(text)
    }

    private nonisolated static func focusedElement() -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(focused as AnyObject, to: AXUIElement.self)
    }

    private nonisolated static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    /// Something you can type into: a text role, or anything exposing a caret.
    private nonisolated static func isTextInput(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let role = role as? String, textRoles.contains(role) {
            return true
        }
        if selectedRange(of: element) != nil { return true }
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    /// `range` is the element's current selected range, already read by the caller.
    private nonisolated static func characterBeforeCaret(in element: AXUIElement, at range: CFRange) -> Character? {
        guard range.location > 0 else { return nil }

        var probe = CFRange(location: range.location - 1, length: 1)
        if let parameter = AXValueCreate(.cfRange, &probe) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value
            ) == .success, let string = value as? String, let last = string.last {
                return last
            }
        }

        // Fallback for fields without the parameterized attribute — only when the value is
        // small enough that reading it whole is cheap.
        var count: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
              let length = (count as? NSNumber)?.intValue, length <= 20_000
        else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let string = value as? String
        else { return nil }
        let units = string.utf16
        guard range.location <= units.count else { return nil }
        return String(decoding: Array(units.prefix(range.location)), as: UTF16.self).last
    }

    /// `before` is the selected range read just before this call (nil when unreadable).
    private nonisolated static func insertViaAccessibility(
        _ text: String,
        into element: AXUIElement,
        before: CFRange?
    ) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else { return false }

        // Without a readable insertion point there's no way to tell a real insert from a
        // silently-dropped one, so don't gamble — go straight to the fallback.
        guard let before else { return false }

        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else { return false }

        guard let after = selectedRange(of: element) else {
            // The write was accepted but can't be checked. Pasting now risks typing it twice,
            // and a duplicated paragraph is worse than trusting the app.
            Log.inject.info("AX write accepted, range unreadable afterwards — trusting it")
            return true
        }

        // Deliberately a *movement* check, not an exact-length check. Falling back after a
        // write that actually landed would paste the text a second time, and a duplicated
        // paragraph is far worse than a missing one. Some apps normalize newlines or run
        // autocorrect, so the caret can legitimately advance by something other than the
        // UTF-16 count — only a completely unmoved selection proves nothing happened.
        let unchanged = after.location == before.location && after.length == before.length
        if unchanged { Log.inject.info("AX write didn't move the caret — pasting instead") }
        return !unchanged
    }

    private nonisolated static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    // MARK: - Which apps fake AX success

    /// Chromium browsers, terminals and well-known Electron apps: AX writes are accepted and
    /// dropped, or the AX tree isn't built until an assistive app asks for it.
    private static let pasteFirstBundleIDs: Set<String> = [
        // Chromium browsers
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "company.thebrowser.dia", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "org.chromium.Chromium", "ai.perplexity.comet",
        // Firefox's AX text support is partial too
        "org.mozilla.firefox", "app.zen-browser.zen",
        // Terminals
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "io.alacritty", "org.alacritty", "com.github.wez.wezterm",
        "co.zeit.hyper", "com.mitchellh.ghostty",
        // Electron and other web-view apps
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "notion.id", "md.obsidian",
        "com.linear", "com.figma.Desktop", "com.anthropic.claudefordesktop",
        "com.exafunction.windsurf", "dev.zed.Zed", "com.microsoft.teams2",
        "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "org.whispersystems.signal-desktop",
    ]

    /// Electron apps not on the list are recognized by their bundled framework.
    private static var electronCache: [String: Bool] = [:]

    private static func prefersPasteboard(_ app: NSRunningApplication?) -> Bool {
        guard let app, let bundleID = app.bundleIdentifier else { return false }
        if pasteFirstBundleIDs.contains(bundleID) { return true }
        if let cached = electronCache[bundleID] { return cached }
        let isElectron = app.bundleURL.map {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        } ?? false
        electronCache[bundleID] = isElectron
        return isElectron
    }

    // MARK: - Pasteboard + ⌘V

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    /// nspasteboard.org markers: clipboard managers skip items carrying these, so a dictation
    /// passing through the clipboard doesn't pollute the user's clipboard history.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    /// The user's own clipboard, waiting to be put back after a paste.
    private static var pendingRestore: (snapshot: Snapshot, task: Task<Void, Never>)?

    private static func paste(_ text: String, restoreClipboard: Bool) async {
        let pasteboard = NSPasteboard.general

        // A restore still pending from a dictation a moment ago holds the *user's* clipboard;
        // the pasteboard right now holds that dictation. Carry the user's forward.
        var saved: Snapshot?
        if restoreClipboard {
            saved = pendingRestore?.snapshot ?? snapshot(of: pasteboard)
        }
        cancelPendingRestore()

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if restoreClipboard {
            item.setData(Data(), forType: transientType)
            item.setData(Data(), forType: autoGeneratedType)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount

        // Give the target app a moment to observe the new pasteboard generation before
        // ⌘V arrives, or a fast paste can grab the *previous* contents.
        try? await Task.sleep(for: .milliseconds(40))
        postCommandV()
        Log.inject.info("pasted (\(text.count) chars)")

        guard let saved, !saved.isEmpty else { return }
        // The paste is asynchronous in the target app; restore only once it's had time to read.
        // The task reads the snapshot back from `pendingRestore` rather than capturing it, so
        // a newer paste can take it over by cancelling this one.
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, let pending = pendingRestore else { return }
            pendingRestore = nil
            // Someone copied something since: theirs wins.
            guard NSPasteboard.general.changeCount == ours else { return }
            restore(pending.snapshot, to: .general)
        }
        pendingRestore = (saved, task)
    }

    private static func cancelPendingRestore() {
        pendingRestore?.task.cancel()
        pendingRestore = nil
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }
    }

    private static func restore(_ saved: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let vKey = keyCodeForCommandV()

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        // Set explicitly rather than inheriting live hardware modifier state — the user may
        // still be resting a finger on something.
        down.flags = .maskCommand
        up.flags = .maskCommand
        // So our own hotkey tap doesn't read this ⌘V as a chord during the next dictation.
        down.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticEventTag)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// The key that types "v" with ⌘ held in the current layout. Shortcuts follow the layout,
    /// so on Dvorak the ANSI "V" position would send ⌘. (Cancel in many apps). Translating
    /// the ⌘ layer also covers "Dvorak – QWERTY ⌘", and layouts with no Latin "v" fall back
    /// to the ANSI position, which is what macOS uses for their shortcuts.
    private static func keyCodeForCommandV() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, "TISPropertyUnicodeKeyLayoutData" as CFString)
        else { return fallback }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { raw -> CGKeyCode in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return fallback }
            let keyboardType = UInt32(LMGetKbdType())
            let commandState = UInt32((cmdKey >> 8) & 0xFF)
            let lowercaseV: UniChar = 0x76
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout,
                    UInt16(code),
                    UInt16(kUCKeyActionDisplay),
                    commandState,
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
                if status == noErr, length == 1, characters[0] == lowercaseV {
                    return CGKeyCode(code)
                }
            }
            return fallback
        }
    }
}
