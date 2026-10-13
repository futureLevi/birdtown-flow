import Foundation
import Testing

@testable import MurmurDictionary

/// Runs every case in `dictionary-test-vectors.json` through `DictionaryCorrector`.
///
/// The file is the reference for how corrections behave. To change that behaviour, change or
/// add a case there first, then the code.
struct CorrectionVectorTests {
    /// The JSON file. Keys the tests don't read, like "$comment" and "note", are ignored.
    struct VectorFile: Decodable {
        let cases: [Vector]
    }

    struct Vector: Decodable {
        let name: String
        let dictionary: [EntryRecord]
        let transcript: String
        let corrected: String
        /// Every correction the case should report, in any order.
        let corrections: [AppliedCorrection]
    }

    struct EntryRecord: Decodable {
        let kind: DictionaryEntry.Kind
        let write: String
        let hear: String?
        let isEnabled: Bool?

        var dictionaryEntry: DictionaryEntry {
            DictionaryEntry(kind: kind, write: write, hear: hear ?? "", isEnabled: isEnabled ?? true)
        }
    }

    static func loadVectors() throws -> [Vector] {
        let url = try #require(
            Bundle.module.url(forResource: "dictionary-test-vectors", withExtension: "json"))
        return try JSONDecoder().decode(VectorFile.self, from: Data(contentsOf: url)).cases
    }

    /// The order corrections are reported in isn't part of the behaviour, so compare sorted.
    static func inOrder(_ corrections: [AppliedCorrection]) -> [AppliedCorrection] {
        corrections.sorted { ($0.to, $0.from, $0.count) < ($1.to, $1.from, $1.count) }
    }

    @Test("every vector gives the expected text and corrections")
    func everyVector() throws {
        let vectors = try Self.loadVectors()
        #expect(!vectors.isEmpty)
        #expect(Set(vectors.map(\.name)).count == vectors.count, "case names should be unique")

        for vector in vectors {
            let corrector = DictionaryCorrector(entries: vector.dictionary.map(\.dictionaryEntry))
            let result = corrector.apply(to: vector.transcript)
            #expect(result.text == vector.corrected, "\(vector.name)")
            #expect(Self.inOrder(result.applied) == Self.inOrder(vector.corrections), "\(vector.name)")
        }
    }

    @Test("a corrector without enabled corrections is empty and leaves text alone")
    func emptyCorrector() {
        var switchedOff = DictionaryEntry.correction(hear: "bird town", write: "Birdtown")
        switchedOff.isEnabled = false
        let corrector = DictionaryCorrector(entries: [.term("Birdtown"), switchedOff])

        #expect(corrector.isEmpty)
        #expect(corrector.apply(to: "bird town").text == "bird town")
        #expect(!DictionaryCorrector(entries: [.correction(hear: "bird town", write: "Birdtown")]).isEmpty)
    }
}

/// `DictionaryCorrector.biasPhrases(from:)`, the hint list handed to the speech engine.
struct BiasPhraseTests {
    @Test("the list stops at the limit and skips repeats that differ only in case")
    func capAndRepeats() {
        let repeats: [DictionaryEntry] = [.term("Birdtown"), .term("birdtown"), .term("  BIRDTOWN ")]
        let entries = repeats + (1...60).map { DictionaryEntry.term("Flow \($0)") }
        let hints = DictionaryCorrector.biasPhrases(from: entries)

        #expect(DictionaryCorrector.biasLimit == 40)
        #expect(hints.count == 40)
        #expect(Array(hints.prefix(2)) == ["Birdtown", "Flow 1"])
        #expect(hints.last == "Flow 39")
    }

    @Test("hints are the trimmed write side of enabled entries, in order")
    func sources() {
        var switchedOff = DictionaryEntry.term("Parakeet")
        switchedOff.isEnabled = false
        let entries: [DictionaryEntry] = [
            .correction(hear: "fluid audio", write: " FluidAudio "),
            switchedOff,
            .term("   "),
            .term("Birdtown Flow"),
        ]

        #expect(DictionaryCorrector.biasPhrases(from: entries) == ["FluidAudio", "Birdtown Flow"])
    }
}

/// `DictionaryWarning.check(_:)`.
struct DictionaryWarningTests {
    @Test(
        "an everyday word as the whole trigger gets one warning",
        arguments: ["flow", "Bird", "the", " data "])
    func everydayWord(trigger: String) {
        #expect(DictionaryWarning.check(.correction(hear: trigger, write: "Birdtown")).count == 1)
    }

    @Test("a very short trigger gets one warning", arguments: ["ux", "zed", "k8s"])
    func shortTrigger(trigger: String) {
        #expect(DictionaryWarning.check(.correction(hear: trigger, write: "Birdtown")).count == 1)
    }

    @Test(
        "phrases and longer unusual words get no warning",
        arguments: ["bird town", "get-hub", "parrot keet", "kubernetes"])
    func distinctiveTrigger(trigger: String) {
        #expect(DictionaryWarning.check(.correction(hear: trigger, write: "Birdtown")).isEmpty)
    }

    @Test("a rule that writes back its own trigger is flagged")
    func rewritesToItself() {
        #expect(DictionaryWarning.check(.correction(hear: "Birdtown", write: "birdtown ")).count == 1)

        let both = DictionaryWarning.check(.correction(hear: "flow", write: "Flow"))
        #expect(both.count == 2)
        #expect(Set(both.map(\.id)).count == both.count)
    }

    @Test("terms and blank triggers are never flagged")
    func nothingToMatch() {
        #expect(DictionaryWarning.check(.term("the")).isEmpty)
        #expect(DictionaryWarning.check(.correction(hear: "  ", write: "Birdtown")).isEmpty)
    }
}
