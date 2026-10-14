import AppKit
import ApplicationServices
import Carbon
import Foundation

/// Types dictated text into the app the user is in, at the caret.
///
/// There are two ways to get it there. The Accessibility API can replace the focused
/// element's selection directly, which is instant and leaves the clipboard alone. Failing
/// that, the text goes on the clipboard and the app gets a ⌘V, with the user's own
/// clipboard put back afterwards.
///
/// The Accessibility route can't be taken at its word. Plenty of apps (Chromium and
/// Electron ones, most terminals) say the selection is writable, report success, and then
/// ignore what they were given. So a write only counts when the caret can be seen to move,
/// and apps known to behave this way go straight to pasting.
///
/// "The focused element" is still the user's text field because the HUD never takes focus:
/// it's a non-activating panel, so their app stays frontmost throughout.
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

    /// Where `insertMeasured` spent its time, for the timing summary: the Accessibility pass
    /// (finding the field, the spacing probe and any AX write) and the paste, its short wait
    /// for the target app included. `nil` for a step that didn't run.
    struct Timings: Sendable, Equatable {
        var accessibilityMs: Int?
        var pasteMs: Int?
    }

    /// Inserts `text` at the caret, or leaves it on the clipboard when there's nowhere to type.
    static func insert(_ text: String, restoreClipboard: Bool) async -> Outcome {
        await insertMeasured(text, restoreClipboard: restoreClipboard).outcome
    }

    /// `insert`, and how long its steps took.
    static func insertMeasured(_ text: String, restoreClipboard: Bool) async -> (outcome: Outcome, timings: Timings) {
        var timings = Timings()
        guard !text.isEmpty else { return (outcome: .inserted, timings: timings) }
        configureMessagingTimeout()

        // Typing into a password prompt is never right, even if it would work.
        if IsSecureEventInputEnabled() {
            copy(text)
            return (outcome: .copied(.secureInput), timings: timings)
        }
        guard AXIsProcessTrusted() else {
            copy(text)
            return (outcome: .copied(.noAccessibility), timings: timings)
        }

        let pasteFirst = prefersPasteboard(NSWorkspace.shared.frontmostApplication)

        // Every AX call blocks until the target app answers, and the hotkey's event tap lives
        // on the main run loop, so the probe and write run on their own queue: a slow app
        // stalls this dictation, not the keyboard. The decisions are the same as on main.
        let clock = ContinuousClock()
        let accessibilityStart = clock.now
        let attempt = await withCheckedContinuation { (continuation: CheckedContinuation<AXAttempt, Never>) in
            axQueue.async {
                continuation.resume(returning: attemptViaAccessibility(text, pasteFirst: pasteFirst))
            }
        }
        timings.accessibilityMs = milliseconds(accessibilityStart.duration(to: clock.now))

        switch attempt {
        case .noTextField:
            copy(text)
            return (outcome: .copied(.noTextField), timings: timings)
        case .inserted:
            return (outcome: .inserted, timings: timings)
        case .needsPaste(let spacedText):
            let pasteStart = clock.now
            await paste(spacedText, restoreClipboard: restoreClipboard)
            timings.pasteMs = milliseconds(pasteStart.duration(to: clock.now))
            return (outcome: .inserted, timings: timings)
        }
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int((duration / Duration.milliseconds(1)).rounded())
    }

    /// Puts `text` on the clipboard as an ordinary copy (clipboard managers keep it).
    static func copy(_ text: String) {
        cancelPendingRestore()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
            Log.inject.info("AX insert landed, \(text.count) chars")
            return .inserted
        }
        return .needsPaste(text)
    }

    /// One attribute of `element`, or `nil` when the app has no value for it (or doesn't
    /// answer in time).
    private nonisolated static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// Whether the app says `name` can be written. Plenty of apps say so and then ignore the
    /// write; see `insertViaAccessibility`.
    private nonisolated static func canSet(_ name: String, on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
            && settable.boolValue
    }

    private nonisolated static func focusedElement() -> AXUIElement? {
        guard let value = attribute(kAXFocusedUIElementAttribute, of: AXUIElementCreateSystemWide()),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
    }

    private nonisolated static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    /// Something you can type into: a text role, or anything exposing a caret.
    private nonisolated static func isTextInput(_ element: AXUIElement) -> Bool {
        if let role = attribute(kAXRoleAttribute, of: element) as? String, textRoles.contains(role) {
            return true
        }
        return selectedRange(of: element) != nil || canSet(kAXSelectedTextAttribute, on: element)
    }

    /// The selection (or, at zero length, the caret) as a UTF-16 range, when the app reports one.
    private nonisolated static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let wrapped = unsafeDowncast(value as AnyObject, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(wrapped) == .cfRange, AXValueGetValue(wrapped, .cfRange, &range) else { return nil }
        return range
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
        guard let length = (attribute(kAXNumberOfCharactersAttribute, of: element) as? NSNumber)?.intValue,
              length <= 20_000,
              let string = attribute(kAXValueAttribute, of: element) as? String
        else { return nil }
        let units = string.utf16
        guard range.location <= units.count else { return nil }
        return String(decoding: Array(units.prefix(range.location)), as: UTF16.self).last
    }

    /// Writes `text` over the selection and reports whether it really landed. `before` is the
    /// selected range the caller read just beforehand; without it there'd be nothing to
    /// compare against, so the paste route is safer.
    private nonisolated static func insertViaAccessibility(
        _ text: String,
        into element: AXUIElement,
        before: CFRange?
    ) -> Bool {
        guard let before, canSet(kAXSelectedTextAttribute, on: element) else { return false }
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard status == .success else { return false }

        guard let after = selectedRange(of: element) else {
            // The write was accepted but can't be checked. Pasting now risks typing it twice,
            // and a duplicated paragraph is worse than trusting the app.
            Log.inject.info("AX write accepted, range unreadable afterwards — trusting it")
            return true
        }

        // An app that ignored the write leaves the selection exactly where it was, so that's
        // the only result treated as failure. Don't expect the caret to move by the text's
        // length: some apps rewrite what they're given (line endings, autocorrect), and
        // calling that a failure would paste the same text again on top of it.
        let moved = after.location != before.location || after.length != before.length
        if !moved { Log.inject.info("AX write didn't move the caret — pasting instead") }
        return moved
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

    /// Everything that was on a pasteboard, every item in every type, so it can be put back.
    @MainActor
    private struct ClipboardContents {
        let items: [[NSPasteboard.PasteboardType: Data]]

        init(of pasteboard: NSPasteboard) {
            items = (pasteboard.pasteboardItems ?? []).map { item in
                item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { saved, type in
                    saved[type] = item.data(forType: type)
                }
            }
        }

        var isEmpty: Bool { items.isEmpty }

        func write(to pasteboard: NSPasteboard) {
            let restored = items.map { saved -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for entry in saved { item.setData(entry.value, forType: entry.key) }
                return item
            }
            pasteboard.clearContents()
            pasteboard.writeObjects(restored)
        }
    }

    /// nspasteboard.org markers: clipboard managers skip items carrying these, so a dictation
    /// passing through the clipboard doesn't pollute the user's clipboard history.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    /// Between putting the text on the clipboard and sending ⌘V. An app that reacts quickly
    /// can otherwise paste before it has noticed the clipboard changed, and get the old one.
    private static let pasteSettleDelay: Duration = .milliseconds(40)

    /// Between ⌘V and putting the user's clipboard back. The app reads the clipboard in its
    /// own time; restoring sooner could hand it the old contents instead of the dictation.
    private static let restoreDelay: Duration = .milliseconds(550)

    /// The user's own clipboard, waiting to be put back after a paste.
    private static var pendingRestore: (contents: ClipboardContents, task: Task<Void, Never>)?

    private static func paste(_ text: String, restoreClipboard: Bool) async {
        let pasteboard = NSPasteboard.general

        // A restore still pending from a dictation a moment ago holds the *user's* clipboard;
        // the pasteboard right now holds that dictation. Carry the user's forward.
        let saved: ClipboardContents? = restoreClipboard
            ? pendingRestore?.contents ?? ClipboardContents(of: pasteboard)
            : nil
        cancelPendingRestore()

        pasteboard.clearContents()
        pasteboard.writeObjects([pasteItem(for: text, transient: restoreClipboard)])
        let ourChange = pasteboard.changeCount

        try? await Task.sleep(for: pasteSettleDelay)
        postCommandV()
        Log.inject.info("sent ⌘V for \(text.count) chars")

        guard let saved, !saved.isEmpty else { return }
        scheduleRestore(saved, unlessChangedSince: ourChange)
    }

    /// The dictation as a pasteboard item, marked transient when the user's clipboard is
    /// coming back afterwards.
    private static func pasteItem(for text: String, transient: Bool) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient {
            item.setData(Data(), forType: transientType)
            item.setData(Data(), forType: autoGeneratedType)
        }
        return item
    }

    /// Puts `contents` back after `restoreDelay`, unless the clipboard has changed since
    /// `changeCount` (the user copied something else, and theirs wins). The task looks the
    /// contents up in `pendingRestore` when it fires instead of keeping its own copy, so a
    /// paste arriving first can cancel it and carry them forward.
    private static func scheduleRestore(_ contents: ClipboardContents, unlessChangedSince changeCount: Int) {
        let task = Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            guard !Task.isCancelled, let pending = pendingRestore else { return }
            pendingRestore = nil
            guard NSPasteboard.general.changeCount == changeCount else { return }
            pending.contents.write(to: .general)
        }
        pendingRestore = (contents, task)
    }

    private static func cancelPendingRestore() {
        pendingRestore?.task.cancel()
        pendingRestore = nil
    }

    /// Sends ⌘V to whatever app is frontmost.
    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let key = keyCodeForCommandV()
        let strokes = [true, false].compactMap { isDown in
            CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
        }
        // Both halves or nothing: a key-down with no key-up would leave V held.
        guard strokes.count == 2 else { return }
        for stroke in strokes {
            // Only ⌘, whatever the user still has a finger on: with ⇧ or ⌥ added, many apps
            // read it as a different command (Paste and Match Style, and so on).
            stroke.flags = .maskCommand
            // So our own hotkey tap doesn't read this ⌘V as a chord during the next dictation.
            stroke.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticEventTag)
        }
        strokes.forEach { $0.post(tap: .cghidEventTap) }
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
