import Foundation

/// What a shortcut does in Birdtown Flow.
public enum ShortcutRole: String, CaseIterable, Sendable {
    case pushToTalk
    case handsFree
    case pasteLast

    /// Ends "… is already used for": "push to talk".
    public var usedFor: String {
        switch self {
        case .pushToTalk: "push to talk"
        case .handsFree: "hands-free"
        case .pasteLast: "pasting your last dictation"
        }
    }

    /// Only push-to-talk can be a modifier held on its own. The others fire on a key press, so
    /// they need a key.
    public var allowsLoneModifier: Bool { self == .pushToTalk }
}

/// Whether a recorded shortcut can be used, and if not, why.
public enum ShortcutVerdict: Equatable, Sendable {
    case accepted
    /// Usable, with a side effect worth knowing ("⌥E types é; this will take it over").
    case caution(String)
    case rejected(String)

    public var isAccepted: Bool {
        if case .rejected = self { return false }
        return true
    }

    public var message: String? {
        switch self {
        case .accepted: nil
        case .caution(let message), .rejected(let message): message
        }
    }
}

/// Decides whether a shortcut is safe to use: not one macOS keeps for itself, not a key you
/// type with, not already taken by another Birdtown Flow action.
public enum ShortcutRules {
    /// - Parameter inUse: the shortcuts other actions use now. The entry for `role` itself is
    ///   ignored, so re-recording the same shortcut is fine.
    public static func check(
        _ shortcut: KeyShortcut,
        for role: ShortcutRole,
        inUse: [ShortcutRole: KeyShortcut] = [:]
    ) -> ShortcutVerdict {
        if let other = ShortcutRole.allCases.first(where: { $0 != role && inUse[$0] == shortcut }) {
            return .rejected("\(shortcut.displayName) is already used for \(other.usedFor).")
        }
        switch shortcut {
        case .modifier(let key):
            return check(key, for: role)
        case .keys(let chord):
            return check(chord)
        }
    }

    private static func check(_ key: ModifierKey, for role: ShortcutRole) -> ShortcutVerdict {
        guard role.allowsLoneModifier else {
            return .rejected("Add a key: hold ⌃, ⌥ or ⌘ and press a letter, like ⌃⌥Space.")
        }
        if key.family == .shift {
            return .caution("Holding \(key.spokenName) on its own will start dictation. Typing capitals still works.")
        }
        if key.isLeftSide {
            return .caution("You use \(key.spokenName) in shortcuts. They keep working, but holding it on its own starts dictation.")
        }
        return .accepted
    }

    private static func check(_ chord: KeyChord) -> ShortcutVerdict {
        if chord.keyCode == KeyCode.escape {
            return .rejected("Esc cancels a dictation, so it can't be a shortcut.")
        }
        if chord.keyCode == KeyCode.capsLock {
            return .rejected("Caps Lock can't be a shortcut. Try a key with ⌃, ⌥ or ⌘.")
        }
        if let reason = reserved[chord] {
            return .rejected(reason)
        }
        let isFunctionKey = KeyNames.isFunctionKey(chord.keyCode)
        if chord.modifiers.isEmpty || chord.modifiers == .shift, !isFunctionKey {
            return .rejected("You type with \(chord.displayName), so it would start dictation mid-sentence. Add ⌃, ⌥ or ⌘.")
        }
        if !isFunctionKey, chord.modifiers == .option || chord.modifiers == [.option, .shift] {
            return .caution("\(chord.displayName) types a special character. Birdtown Flow will take it over in every app.")
        }
        if !isFunctionKey, chord.modifiers == .command || chord.modifiers == [.command, .shift] {
            return .caution("Apps often use \(chord.displayName) for their own commands. Birdtown Flow will take it over in every app.")
        }
        return .accepted
    }

    /// Shortcuts macOS, or every app, already uses, with the reason shown when one is refused.
    static let reserved: [KeyChord: String] = {
        var table: [KeyChord: String] = [:]
        func add(_ code: UInt16, _ modifiers: ShortcutModifiers, _ reason: (String) -> String) {
            let chord = KeyChord(keyCode: code, modifiers: modifiers)
            table[chord] = reason(chord.displayName)
        }
        add(KeyCode.space, [.command]) { "Spotlight uses \($0)." }
        add(KeyCode.space, [.control]) { "macOS switches input sources with \($0)." }
        add(KeyCode.space, [.control, .option]) { "macOS switches input sources with \($0)." }
        add(KeyCode.space, [.option, .command]) { "Finder search uses \($0)." }
        add(KeyCode.space, [.control, .command]) { "macOS opens the emoji picker with \($0)." }
        add(KeyCode.tab, [.command]) { "The app switcher uses \($0)." }
        add(KeyCode.tab, [.command, .shift]) { "The app switcher uses \($0)." }
        add(KeyCode.grave, [.command]) { "macOS switches between an app's windows with \($0)." }
        add(KeyCode.grave, [.command, .shift]) { "macOS switches between an app's windows with \($0)." }
        for code in [KeyCode.three, KeyCode.four, KeyCode.five] {
            add(code, [.command, .shift]) { "macOS takes screenshots with \($0)." }
            add(code, [.control, .command, .shift]) { "macOS takes screenshots with \($0)." }
        }
        add(KeyCode.q, [.control, .command]) { "\($0) locks your Mac." }
        add(KeyCode.f, [.control, .command]) { "\($0) turns full screen on and off." }
        add(KeyCode.d, [.option, .command]) { "\($0) shows and hides the Dock." }
        add(KeyCode.h, [.option, .command]) { "\($0) hides other apps." }
        add(KeyCode.leftArrow, [.control]) { "macOS moves between Spaces with \($0)." }
        add(KeyCode.rightArrow, [.control]) { "macOS moves between Spaces with \($0)." }
        add(KeyCode.upArrow, [.control]) { "\($0) opens Mission Control." }
        add(KeyCode.downArrow, [.control]) { "\($0) shows the app's windows." }
        let everyApp: [(UInt16, String)] = [
            (KeyCode.q, "quits"), (KeyCode.w, "closes the window"), (KeyCode.h, "hides the app"),
            (KeyCode.m, "minimises the window"), (KeyCode.c, "copies"), (KeyCode.v, "pastes"),
            (KeyCode.x, "cuts"), (KeyCode.z, "undoes"), (KeyCode.a, "selects all"),
            (KeyCode.s, "saves"), (KeyCode.f, "finds"), (KeyCode.n, "opens a new window"),
            (KeyCode.o, "opens a file"), (KeyCode.p, "prints"), (KeyCode.t, "opens a new tab"),
            (KeyCode.comma, "opens settings"),
        ]
        for (code, action) in everyApp {
            add(code, [.command]) { "\($0) \(action) in every app." }
        }
        add(KeyCode.z, [.command, .shift]) { "\($0) redoes in every app." }
        return table
    }()
}
