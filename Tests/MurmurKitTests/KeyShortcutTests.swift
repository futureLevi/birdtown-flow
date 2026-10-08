import Testing
@testable import MurmurKit

@Suite("KeyShortcut")
struct KeyShortcutTests {
    // Event flags as macOS reports them: device-independent bit plus the side's device bit.
    static let rightOptionDown: UInt64 = ShortcutModifiers.option.rawValue | 0x40
    static let leftOptionDown: UInt64 = ShortcutModifiers.option.rawValue | 0x20
    static let leftControlDown: UInt64 = ShortcutModifiers.control.rawValue | 0x01
    static let fnDown: UInt64 = ModifierKey.functionFlag

    @Test("Push-to-talk keys saved before custom shortcuts still load, and save the same way")
    func legacyStorage() {
        let legacy: [String: KeyShortcut] = [
            "fn": .fn, "rightOption": .rightOption, "rightCommand": .rightCommand, "rightControl": .rightControl,
        ]
        for (saved, expected) in legacy {
            #expect(KeyShortcut(storageValue: saved) == expected)
            #expect(expected.storageValue == saved)
        }
        #expect(KeyShortcut(storageValue: "") == nil)
        #expect(KeyShortcut(storageValue: "middleMouse") == nil)
    }

    @Test("Chords round-trip through storage, label included")
    func chordStorage() {
        let chord = KeyChord(keyCode: KeyCode.d, modifiers: [.control, .option], keyLabel: "d")
        let saved = KeyShortcut.keys(chord).storageValue
        #expect(saved == "keys:2:control+option:D")
        let loaded = KeyShortcut(storageValue: saved)
        #expect(loaded == .keys(chord))
        #expect(loaded?.chord?.keyLabel == "D")

        let colon = KeyChord(keyCode: 0x29, modifiers: [.command, .shift], keyLabel: ":")
        #expect(KeyChord(storageValue: colon.storageValue)?.keyLabel == ":")

        let bare = KeyChord(keyCode: KeyCode.functionKeys[4], modifiers: [])
        #expect(KeyChord(storageValue: bare.storageValue) == bare)
        #expect(bare.displayName == "F5")
        #expect(KeyChord(storageValue: "keys:9:hyper:V") == nil)
        #expect(KeyChord(storageValue: "keys:x:control:V") == nil)
    }

    @Test("Equality ignores the label, which is display only")
    func labelIgnored() {
        let us = KeyChord(keyCode: KeyCode.z, modifiers: [.control], keyLabel: "Z")
        let german = KeyChord(keyCode: KeyCode.z, modifiers: [.control], keyLabel: "Y")
        #expect(us == german)
        #expect(Set([us, german]).count == 1)
    }

    @Test("Names: glyphs in menu order, spoken names for VoiceOver")
    func names() {
        let chord = KeyChord(keyCode: KeyCode.space, modifiers: [.command, .shift, .control, .option])
        #expect(chord.glyphs == ["⌃", "⌥", "⇧", "⌘", "Space"])
        #expect(chord.spokenName == "Control Option Shift Command Space")
        #expect(KeyShortcut.fn.displayName == "fn")
        #expect(KeyShortcut.rightOption.displayName == "Right ⌥")
        #expect(KeyShortcut.modifier(.leftCommand).spokenName == "Left Command")
        #expect(KeyShortcut.fn.spokenName == "Fn (Globe)")
        #expect(KeyChord.pasteLastDefault.displayName == "⌃⌥V")
    }

    @Test("A chord matches exactly its modifiers, ignoring fn, caps lock and the side")
    func matching() {
        let chord = KeyChord(keyCode: KeyCode.d, modifiers: [.control, .option])
        let both = Self.leftControlDown | Self.rightOptionDown
        #expect(chord.matches(keyCode: KeyCode.d, eventFlags: both))
        #expect(chord.matches(keyCode: KeyCode.d, eventFlags: both | Self.fnDown | 0x1_0000))
        #expect(!chord.matches(keyCode: KeyCode.d, eventFlags: both | ShortcutModifiers.shift.rawValue))
        #expect(!chord.matches(keyCode: KeyCode.d, eventFlags: Self.leftControlDown))
        #expect(!chord.matches(keyCode: KeyCode.s, eventFlags: both))
    }

    @Test("Carbon flags convert both ways")
    func carbon() {
        let modifiers: ShortcutModifiers = [.control, .option]
        #expect(modifiers.carbonFlags == 0x1000 | 0x0800)
        #expect(ShortcutModifiers(carbonFlags: 0x1000 | 0x0800) == modifiers)
        #expect(ShortcutModifiers(carbonFlags: 0x0100 | 0x0200) == [.command, .shift])
    }

    @Test("Modifier keys tell left from right")
    func sides() {
        #expect(ModifierKey.rightOption.isDown(in: Self.rightOptionDown))
        #expect(!ModifierKey.rightOption.isDown(in: Self.leftOptionDown))
        #expect(ModifierKey.leftOption.isDown(in: Self.leftOptionDown))
        #expect(ModifierKey(keyCode: 61) == .rightOption)
        #expect(ModifierKey(keyCode: 63) == .function)
        #expect(ModifierKey(keyCode: 0) == nil)
    }

    @Test("Labels: named keys use symbols, others what the layout typed, else US")
    func labels() {
        #expect(KeyNames.label(for: KeyCode.returnKey, typed: "\r") == "↩")
        #expect(KeyNames.label(for: KeyCode.z, typed: "y") == "Y")
        #expect(KeyNames.label(for: KeyCode.z, typed: nil) == "Z")
        #expect(KeyNames.label(for: KeyCode.z, typed: "") == "Z")
        #expect(KeyNames.label(for: KeyCode.functionKeys[12]) == "F13")
    }
}

@Suite("ShortcutRules")
struct ShortcutRulesTests {
    private func chord(_ code: UInt16, _ modifiers: ShortcutModifiers) -> KeyShortcut {
        .keys(KeyChord(keyCode: code, modifiers: modifiers))
    }

    @Test("The quick picks are all fine for push to talk")
    func quickPicks() {
        for key in KeyShortcut.quickPicks {
            #expect(ShortcutRules.check(key, for: .pushToTalk) == .accepted)
        }
    }

    @Test("System shortcuts are refused, with the reason")
    func systemShortcuts() {
        let spotlight = ShortcutRules.check(chord(KeyCode.space, [.command]), for: .handsFree)
        #expect(spotlight == .rejected("Spotlight uses ⌘Space."))
        let switcher = ShortcutRules.check(chord(KeyCode.tab, [.command]), for: .pushToTalk)
        #expect(!switcher.isAccepted)
        #expect(switcher.message?.contains("app switcher") == true)
        #expect(!ShortcutRules.check(chord(KeyCode.q, [.command]), for: .pasteLast).isAccepted)
        #expect(!ShortcutRules.check(chord(KeyCode.four, [.command, .shift]), for: .pasteLast).isAccepted)
        #expect(!ShortcutRules.check(chord(KeyCode.leftArrow, [.control]), for: .handsFree).isAccepted)
    }

    @Test("Keys you type with need a modifier; function keys don't")
    func typingKeys() {
        #expect(!ShortcutRules.check(chord(KeyCode.d, []), for: .pushToTalk).isAccepted)
        #expect(!ShortcutRules.check(chord(KeyCode.d, [.shift]), for: .pasteLast).isAccepted)
        #expect(!ShortcutRules.check(chord(KeyCode.space, []), for: .handsFree).isAccepted)
        #expect(ShortcutRules.check(chord(KeyCode.functionKeys[4], []), for: .pushToTalk) == .accepted)
        #expect(ShortcutRules.check(chord(KeyCode.d, [.control, .option]), for: .pushToTalk) == .accepted)
    }

    @Test("Esc is never a shortcut: it cancels")
    func escape() {
        #expect(!ShortcutRules.check(chord(KeyCode.escape, [.option, .command]), for: .handsFree).isAccepted)
        #expect(!ShortcutRules.check(chord(KeyCode.escape, []), for: .pushToTalk).isAccepted)
    }

    @Test("Option with a letter and Command alone are allowed, with a caution")
    func cautions() {
        if case .caution = ShortcutRules.check(chord(KeyCode.d, [.option]), for: .pasteLast) {} else {
            Issue.record("⌥D should be a caution")
        }
        if case .caution = ShortcutRules.check(chord(KeyCode.d, [.command]), for: .pasteLast) {} else {
            Issue.record("⌘D should be a caution")
        }
        if case .caution = ShortcutRules.check(.modifier(.leftCommand), for: .pushToTalk) {} else {
            Issue.record("Left ⌘ should be a caution")
        }
        if case .caution = ShortcutRules.check(.modifier(.rightShift), for: .pushToTalk) {} else {
            Issue.record("Right ⇧ should be a caution")
        }
    }

    @Test("A lone modifier is only for push to talk")
    func loneModifier() {
        #expect(ShortcutRules.check(.modifier(.rightOption), for: .pushToTalk) == .accepted)
        #expect(!ShortcutRules.check(.modifier(.rightOption), for: .handsFree).isAccepted)
        #expect(!ShortcutRules.check(.fn, for: .pasteLast).isAccepted)
    }

    @Test("A shortcut another action uses is refused; the same action may keep its own")
    func conflicts() {
        let paste = KeyShortcut.keys(.pasteLastDefault)
        let inUse: [ShortcutRole: KeyShortcut] = [.pushToTalk: .fn, .pasteLast: paste]
        let verdict = ShortcutRules.check(paste, for: .handsFree, inUse: inUse)
        #expect(verdict == .rejected("⌃⌥V is already used for pasting your last dictation."))
        #expect(ShortcutRules.check(paste, for: .pasteLast, inUse: inUse) == .accepted)
        #expect(!ShortcutRules.check(.fn, for: .pushToTalk, inUse: [.handsFree: .fn]).isAccepted)
    }
}

@Suite("ShortcutCapture")
struct ShortcutCaptureTests {
    static let rightOption: UInt64 = ShortcutModifiers.option.rawValue | 0x40
    static let leftControl: UInt64 = ShortcutModifiers.control.rawValue | 0x01

    @Test("A modifier pressed and let go alone is recorded for push to talk")
    func loneModifier() {
        var capture = ShortcutCapture(allowsLoneModifier: true)
        #expect(capture.modifiersChanged(flags: Self.rightOption) == .listening)
        #expect(capture.heldGlyphs == ["Right ⌥"])
        #expect(capture.modifiersChanged(flags: 0) == .captured(.rightOption))
    }

    @Test("fn alone is recorded too")
    func fnAlone() {
        var capture = ShortcutCapture(allowsLoneModifier: true)
        _ = capture.modifiersChanged(flags: ModifierKey.functionFlag)
        #expect(capture.modifiersChanged(flags: 0) == .captured(.fn))
    }

    @Test("Other roles ask for a key instead")
    func needsKey() {
        var capture = ShortcutCapture(allowsLoneModifier: false)
        _ = capture.modifiersChanged(flags: Self.rightOption)
        #expect(capture.modifiersChanged(flags: 0) == .needsKey(.rightOption))
    }

    @Test("Two modifiers then a key record the chord; letting go of modifiers alone records nothing")
    func chord() {
        var capture = ShortcutCapture(allowsLoneModifier: true)
        _ = capture.modifiersChanged(flags: Self.leftControl)
        _ = capture.modifiersChanged(flags: Self.leftControl | Self.rightOption)
        #expect(capture.heldGlyphs == ["⌃", "⌥"])
        let outcome = capture.keyDown(keyCode: KeyCode.d, flags: Self.leftControl | Self.rightOption, typed: "d")
        #expect(outcome == .captured(.keys(KeyChord(keyCode: KeyCode.d, modifiers: [.control, .option]))))

        var abandoned = ShortcutCapture(allowsLoneModifier: true)
        _ = abandoned.modifiersChanged(flags: Self.leftControl)
        _ = abandoned.modifiersChanged(flags: Self.leftControl | Self.rightOption)
        _ = abandoned.modifiersChanged(flags: Self.rightOption)
        #expect(abandoned.modifiersChanged(flags: 0) == .listening)
    }

    @Test("Esc alone cancels; with modifiers it's a chord for the rules to refuse")
    func escape() {
        var capture = ShortcutCapture(allowsLoneModifier: true)
        #expect(capture.keyDown(keyCode: KeyCode.escape, flags: 0) == .cancelled)
        let withCommand = capture.keyDown(keyCode: KeyCode.escape, flags: ShortcutModifiers.command.rawValue)
        #expect(withCommand == .captured(.keys(KeyChord(keyCode: KeyCode.escape, modifiers: [.command]))))
    }
}
