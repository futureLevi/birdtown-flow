import Foundation
import Testing

@testable import MurmurDictionary

/// `DictionaryEntry.carryingIDs` keeps row identity stable when the dictionary file is re-read.
struct CarryingIDsTests {
    @Test("unchanged entries keep their ids")
    func keepsIDs() {
        let existing = [
            DictionaryEntry.term("Anthropic"),
            DictionaryEntry.correction(hear: "cloud code", write: "Claude Code"),
        ]
        let parsed = [
            DictionaryEntry.term("Anthropic"),
            DictionaryEntry.correction(hear: "cloud code", write: "Claude Code"),
        ]
        let result = DictionaryEntry.carryingIDs(from: existing, into: parsed)
        #expect(result == existing)
    }

    @Test("reordered and inserted entries match by content, new ones keep fresh ids")
    func matchesByContent() {
        let a = DictionaryEntry.term("Alpha")
        let b = DictionaryEntry.term("Beta")
        let fresh = DictionaryEntry.term("Gamma")
        let parsed = [fresh, DictionaryEntry.term("Beta"), DictionaryEntry.term("Alpha")]

        let result = DictionaryEntry.carryingIDs(from: [a, b], into: parsed)
        #expect(result.map(\.id) == [fresh.id, b.id, a.id])
        #expect(result.map(\.write) == ["Gamma", "Beta", "Alpha"])
    }

    @Test("a changed entry is not matched")
    func changedEntryGetsNoID() {
        let on = DictionaryEntry.correction(hear: "x", write: "Y")
        var off = DictionaryEntry.correction(hear: "x", write: "Y")
        off.isEnabled = false

        let result = DictionaryEntry.carryingIDs(from: [on], into: [off])
        #expect(result == [off])
    }

    @Test("duplicate lines never share an id")
    func duplicatesStayUnique() {
        let first = DictionaryEntry.term("Same")
        let second = DictionaryEntry.term("Same")
        let parsed = [DictionaryEntry.term("Same"), DictionaryEntry.term("Same"), DictionaryEntry.term("Same")]

        let result = DictionaryEntry.carryingIDs(from: [first, second], into: parsed)
        #expect(result[0].id == first.id)
        #expect(result[1].id == second.id)
        #expect(result[2].id == parsed[2].id)
        #expect(Set(result.map(\.id)).count == 3)
    }
}
