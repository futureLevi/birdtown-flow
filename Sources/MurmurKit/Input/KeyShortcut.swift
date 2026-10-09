import Foundation

// Shortcuts as plain values: which key, which modifiers, how to name them and how to save
// them. The app turns these into event-tap checks and Carbon hot keys; everything here is
// Foundation-only so it is tested on Linux too.
//
// Raw numbers follow macOS: key codes are the `kVK_*` virtual key codes, `ShortcutModifiers`
// uses the device-independent bits of `CGEventFlags`/`NSEvent.ModifierFlags`, and
// `ModifierKey.deviceFlag` the NX_DEVICE* bits that tell left from right.

// MARK: - Modifiers

/// The modifiers in a key combination. Raw values are the device-independent event-flag bits
/// (`CGEventFlags.maskControl` and friends), so the app converts with `rawValue`.
public struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let shift = ShortcutModifiers(rawValue: 0x0002_0000)
    public static let control = ShortcutModifiers(rawValue: 0x0004_0000)
    public static let option = ShortcutModifiers(rawValue: 0x0008_0000)
    public static let command = ShortcutModifiers(rawValue: 0x0010_0000)

    public static let all: ShortcutModifiers = [.control, .option, .shift, .command]

    /// The four modifiers in an event's flags. Caps Lock, fn (which macOS also sets for arrow
    /// and function keys), the numeric-pad bit and the left/right device bits are ignored.
    public init(eventFlags: UInt64) {
        self.init(rawValue: eventFlags & Self.all.rawValue)
    }

    /// From Carbon's `cmdKey`/`shiftKey`/`optionKey`/`controlKey` bits.
    public init(carbonFlags: Int) {
        var modifiers: ShortcutModifiers = []
        for (flag, carbon) in Self.carbonBits where carbonFlags & carbon != 0 {
            modifiers.insert(flag)
        }
        self = modifiers
    }

    /// For `RegisterEventHotKey`.
    public var carbonFlags: Int {
        Self.carbonBits.reduce(0) { result, pair in contains(pair.0) ? result | pair.1 : result }
    }

    /// In the order macOS menus print them: ⌃⌥⇧⌘.
    public var glyphs: [String] { Self.ordered.filter { contains($0.0) }.map { $0.1 } }

    /// "Control", "Option", "Shift", "Command", in menu order.
    public var names: [String] { Self.ordered.filter { contains($0.0) }.map { $0.2 } }

    private static let ordered: [(ShortcutModifiers, String, String)] = [
        (.control, "⌃", "Control"),
        (.option, "⌥", "Option"),
        (.shift, "⇧", "Shift"),
        (.command, "⌘", "Command"),
    ]

    /// cmdKey = 1 << 8, shiftKey = 1 << 9, optionKey = 1 << 11, controlKey = 1 << 12.
    private static let carbonBits: [(ShortcutModifiers, Int)] = [
        (.command, 0x0100), (.shift, 0x0200), (.option, 0x0800), (.control, 0x1000),
    ]

    private static let storageNames: [(ShortcutModifiers, String)] = [
        (.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "command"),
    ]

    /// "control+option"; empty for none.
    var storageValue: String {
        Self.storageNames.filter { contains($0.0) }.map { $0.1 }.joined(separator: "+")
    }

    init?(storageValue: String) {
        var modifiers: ShortcutModifiers = []
        for name in storageValue.split(separator: "+") {
            guard let flag = Self.storageNames.first(where: { $0.1 == name })?.0 else { return nil }
            modifiers.insert(flag)
        }
        self = modifiers
    }
}

// MARK: - A single modifier key

/// One physical modifier key, left and right told apart. Push-to-talk can be any of these.
///
/// Raw values are what Settings saved before custom shortcuts existed ("fn", "rightOption"…),
/// so those saved choices still load.
public enum ModifierKey: String, CaseIterable, Sendable {
    case function = "fn"
    case rightOption
    case rightCommand
    case rightControl
    case rightShift
    case leftOption
    case leftCommand
    case leftControl
    case leftShift

    /// The `kVK_*` code its flags-changed event carries.
    public var keyCode: UInt16 {
        switch self {
        case .function: 63      // kVK_Function
        case .rightOption: 61   // kVK_RightOption
        case .rightCommand: 54  // kVK_RightCommand
        case .rightControl: 62  // kVK_RightControl
        case .rightShift: 60    // kVK_RightShift
        case .leftOption: 58    // kVK_Option
        case .leftCommand: 55   // kVK_Command
        case .leftControl: 59   // kVK_Control
        case .leftShift: 56     // kVK_Shift
        }
    }

    public init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }

    /// The device-*dependent* bit for this physical key: the NX_DEVICE* masks from IOKit,
    /// which carry the left/right distinction that the union bits discard. Hold Left ⌥ and tap
    /// Right ⌥, and only this bit shows Right ⌥ going up. fn has no left/right, so it uses its
    /// one flag.
    public var deviceFlag: UInt64 {
        switch self {
        case .leftControl: 0x0001   // NX_DEVICELCTLKEYMASK
        case .leftShift: 0x0002     // NX_DEVICELSHIFTKEYMASK
        case .rightShift: 0x0004    // NX_DEVICERSHIFTKEYMASK
        case .leftCommand: 0x0008   // NX_DEVICELCMDKEYMASK
        case .rightCommand: 0x0010  // NX_DEVICERCMDKEYMASK
        case .leftOption: 0x0020    // NX_DEVICELALTKEYMASK
        case .rightOption: 0x0040   // NX_DEVICERALTKEYMASK
        case .rightControl: 0x2000  // NX_DEVICERCTLKEYMASK
        case .function: Self.functionFlag
        }
    }

    /// `maskSecondaryFn`.
    public static let functionFlag: UInt64 = 0x0080_0000

    /// Every left/right device bit (fn excluded: it has none).
    public static let deviceMask: UInt64 = 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x2000

    /// The device-independent bit, set while either side is down. Only good for confirming a
    /// release: if even this is clear, the key is certainly up.
    public var unionFlag: UInt64 {
        family?.rawValue ?? Self.functionFlag
    }

    /// The modifier this key applies; `nil` for fn.
    public var family: ShortcutModifiers? {
        switch self {
        case .function: nil
        case .rightOption, .leftOption: .option
        case .rightCommand, .leftCommand: .command
        case .rightControl, .leftControl: .control
        case .rightShift, .leftShift: .shift
        }
    }

    public var isRightSide: Bool {
        switch self {
        case .rightOption, .rightCommand, .rightControl, .rightShift: true
        default: false
        }
    }

    public var isLeftSide: Bool { self != .function && !isRightSide }

    public func isDown(in flags: UInt64) -> Bool { flags & deviceFlag != 0 }

    /// What's printed on the key: "fn", "⌥".
    public var glyph: String {
        switch self {
        case .function: "fn"
        case .rightOption, .leftOption: "⌥"
        case .rightCommand, .leftCommand: "⌘"
        case .rightControl, .leftControl: "⌃"
        case .rightShift, .leftShift: "⇧"
        }
    }

    /// Short form for the HUD and logs: "fn", "Right ⌥", "Left ⌘".
    public var displayName: String {
        if self == .function { return "fn" }
        return "\(isRightSide ? "Right" : "Left") \(glyph)"
    }

    /// Spelled out for captions and VoiceOver: "Fn (Globe)", "Right Option".
    public var spokenName: String {
        if self == .function { return "Fn (Globe)" }
        let word = family.flatMap { $0.names.first } ?? glyph
        return "\(isRightSide ? "Right" : "Left") \(word)"
    }

    /// Menu order for showing several held at once: fn, then ⌃⌥⇧⌘, left before right.
    var sortOrder: Int {
        switch self {
        case .function: 0
        case .leftControl: 1
        case .rightControl: 2
        case .leftOption: 3
        case .rightOption: 4
        case .leftShift: 5
        case .rightShift: 6
        case .leftCommand: 7
        case .rightCommand: 8
        }
    }
}

// MARK: - A key with modifiers

/// A key pressed with modifiers, such as ⌃⌥V, or a function key on its own, such as F5.
public struct KeyChord: Sendable, CustomStringConvertible {
    /// The `kVK_*` code: the key's position, whatever the keyboard layout.
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    /// What the key prints on the user's layout ("V", "Z" on AZERTY's W key), captured when
    /// it was recorded. For display only: two chords are equal when code and modifiers are.
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: ShortcutModifiers, keyLabel: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = KeyNames.label(for: keyCode, typed: keyLabel)
    }

    /// ⌃⌥V, the paste-last default.
    public static let pasteLastDefault = KeyChord(keyCode: KeyCode.v, modifiers: [.control, .option])

    /// Whether a key-down with these values is this chord: same key, exactly these modifiers.
    public func matches(keyCode: UInt16, eventFlags: UInt64) -> Bool {
        keyCode == self.keyCode && ShortcutModifiers(eventFlags: eventFlags) == modifiers
    }

    /// One keycap each: ["⌃", "⌥", "V"].
    public var glyphs: [String] { modifiers.glyphs + [keyLabel] }

    /// "⌃⌥V", "⌘Space".
    public var displayName: String { glyphs.joined() }

    /// "Control Option V", for VoiceOver.
    public var spokenName: String {
        (modifiers.names + [KeyNames.spokenName(for: keyCode, label: keyLabel)]).joined(separator: " ")
    }

    public var description: String { displayName }

    /// "keys:9:control+option:V". The label goes last, so it may contain anything.
    public var storageValue: String {
        "keys:\(keyCode):\(modifiers.storageValue):\(keyLabel)"
    }

    public init?(storageValue: String) {
        let parts = storageValue.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "keys",
              let code = UInt16(parts[1]),
              let modifiers = ShortcutModifiers(storageValue: String(parts[2]))
        else { return nil }
        let label = parts.count == 4 ? String(parts[3]) : nil
        self.init(keyCode: code, modifiers: modifiers, keyLabel: label)
    }
}

extension KeyChord: Hashable {
    public static func == (lhs: KeyChord, rhs: KeyChord) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }
}

// MARK: - Either

/// A shortcut: one modifier key held on its own (fn, Right ⌥), or a key with modifiers (⌃⌥D).
public enum KeyShortcut: Hashable, Sendable, CustomStringConvertible {
    case modifier(ModifierKey)
    case keys(KeyChord)

    public static let fn = KeyShortcut.modifier(.function)
    public static let rightOption = KeyShortcut.modifier(.rightOption)
    public static let rightCommand = KeyShortcut.modifier(.rightCommand)
    public static let rightControl = KeyShortcut.modifier(.rightControl)

    /// The push-to-talk keys offered as one-click choices, fn first: it's the easiest to reach.
    public static let quickPicks: [KeyShortcut] = [.fn, .rightOption, .rightCommand, .rightControl]

    public var isQuickPick: Bool { Self.quickPicks.contains(self) }

    public var modifierKey: ModifierKey? {
        if case .modifier(let key) = self { return key }
        return nil
    }

    public var chord: KeyChord? {
        if case .keys(let chord) = self { return chord }
        return nil
    }

    /// One keycap per key: ["fn"], ["⌥"], ["⌃", "⌥", "D"].
    public var glyphs: [String] {
        switch self {
        case .modifier(let key): [key.glyph]
        case .keys(let chord): chord.glyphs
        }
    }

    /// "fn", "Right ⌥", "⌃⌥D".
    public var displayName: String {
        switch self {
        case .modifier(let key): key.displayName
        case .keys(let chord): chord.displayName
        }
    }

    /// "Fn (Globe)", "Right Option", "Control Option D".
    public var spokenName: String {
        switch self {
        case .modifier(let key): key.spokenName
        case .keys(let chord): chord.spokenName
        }
    }

    public var description: String { displayName }

    /// A modifier saves as its raw value ("fn", "rightOption"), exactly as before custom
    /// shortcuts, so a downgrade still reads it; a chord saves as `KeyChord.storageValue`.
    public var storageValue: String {
        switch self {
        case .modifier(let key): key.rawValue
        case .keys(let chord): chord.storageValue
        }
    }

    public init?(storageValue: String) {
        if let key = ModifierKey(rawValue: storageValue) {
            self = .modifier(key)
        } else if let chord = KeyChord(storageValue: storageValue) {
            self = .keys(chord)
        } else {
            return nil
        }
    }
}

// MARK: - Key codes and names

/// The `kVK_*` virtual key codes the shortcut rules need (Carbon's `Events.h`).
public enum KeyCode {
    public static let a: UInt16 = 0x00
    public static let s: UInt16 = 0x01
    public static let d: UInt16 = 0x02
    public static let f: UInt16 = 0x03
    public static let h: UInt16 = 0x04
    public static let c: UInt16 = 0x08
    public static let v: UInt16 = 0x09
    public static let x: UInt16 = 0x07
    public static let z: UInt16 = 0x06
    public static let q: UInt16 = 0x0C
    public static let w: UInt16 = 0x0D
    public static let t: UInt16 = 0x11
    public static let n: UInt16 = 0x2D
    public static let m: UInt16 = 0x2E
    public static let o: UInt16 = 0x1F
    public static let p: UInt16 = 0x23
    public static let three: UInt16 = 0x14
    public static let four: UInt16 = 0x15
    public static let five: UInt16 = 0x17
    public static let comma: UInt16 = 0x2B
    public static let grave: UInt16 = 0x32
    public static let returnKey: UInt16 = 0x24
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35
    public static let capsLock: UInt16 = 0x39
    public static let help: UInt16 = 0x72
    public static let home: UInt16 = 0x73
    public static let pageUp: UInt16 = 0x74
    public static let forwardDelete: UInt16 = 0x75
    public static let end: UInt16 = 0x77
    public static let pageDown: UInt16 = 0x79
    public static let leftArrow: UInt16 = 0x7B
    public static let rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D
    public static let upArrow: UInt16 = 0x7E
    public static let keypadEnter: UInt16 = 0x4C

    /// F1…F20, in order.
    public static let functionKeys: [UInt16] = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]
}

/// How keys are named on keycaps and to VoiceOver.
public enum KeyNames {
    /// F1…F20: keys that type nothing, so they may be a shortcut on their own.
    public static func isFunctionKey(_ code: UInt16) -> Bool {
        KeyCode.functionKeys.contains(code)
    }

    /// The keycap label. Named keys (Space, ↩, F5) use their fixed symbol; others use what the
    /// key typed on the user's layout (`typed`, captured when recording), falling back to the
    /// US layout.
    public static func label(for code: UInt16, typed: String? = nil) -> String {
        if let special = special[code] { return special.label }
        if let index = KeyCode.functionKeys.firstIndex(of: code) { return "F\(index + 1)" }
        if let typed {
            let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            if !trimmed.isEmpty, trimmed.count <= 3 { return trimmed.uppercased() }
        }
        if let ansi = ansi[code] { return ansi }
        return "Key \(code)"
    }

    /// "Space", "Return", "Left Arrow", "F5"; otherwise the label itself.
    public static func spokenName(for code: UInt16, label: String) -> String {
        special[code]?.spoken ?? label
    }

    private static let special: [UInt16: (label: String, spoken: String)] = [
        KeyCode.returnKey: ("↩", "Return"),
        KeyCode.tab: ("⇥", "Tab"),
        KeyCode.space: ("Space", "Space"),
        KeyCode.delete: ("⌫", "Delete"),
        KeyCode.escape: ("esc", "Escape"),
        KeyCode.help: ("Help", "Help"),
        KeyCode.home: ("↖", "Home"),
        KeyCode.pageUp: ("⇞", "Page Up"),
        KeyCode.forwardDelete: ("⌦", "Forward Delete"),
        KeyCode.end: ("↘", "End"),
        KeyCode.pageDown: ("⇟", "Page Down"),
        KeyCode.leftArrow: ("←", "Left Arrow"),
        KeyCode.rightArrow: ("→", "Right Arrow"),
        KeyCode.downArrow: ("↓", "Down Arrow"),
        KeyCode.upArrow: ("↑", "Up Arrow"),
        KeyCode.keypadEnter: ("⌤", "Enter"),
    ]

    /// The US ANSI layout, for chords saved without a label.
    private static let ansi: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
        0x41: ".", 0x43: "*", 0x45: "+", 0x47: "⌧", 0x4B: "/", 0x4E: "-", 0x51: "=",
        0x52: "0", 0x53: "1", 0x54: "2", 0x55: "3", 0x56: "4", 0x57: "5", 0x58: "6", 0x59: "7",
        0x5B: "8", 0x5C: "9",
    ]
}
