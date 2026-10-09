import Foundation
import MurmurDictionary
import Testing
@testable import MurmurKit

@Suite("LibraryUsage")
struct LibraryUsageStatsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// `AppliedCorrection` only has a memberwise init inside MurmurDictionary; History reads
    /// them back from JSON, so build them the same way.
    func applied(_ from: String, _ to: String, _ count: Int) -> AppliedCorrection {
        let json: [String: Any] = ["from": from, "to": to, "count": count]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(AppliedCorrection.self, from: data)
    }

    func record(corrections: [AppliedCorrection] = [], snippets: [String] = [], at date: Date? = nil) -> HistoryRecord {
        HistoryRecord(createdAt: date ?? now, finalText: "x", corrections: corrections, snippets: snippets)
    }

    @Test("Two replacements writing the same text are counted apart")
    func sharedWriteIsNotMerged() {
        let cloud = DictionaryEntry.correction(hear: "cloud", write: "Claude")
        let clawed = DictionaryEntry.correction(hear: "clawed", write: "Claude")
        let records = [
            record(corrections: [applied("Cloud", "Claude", 2)]),
            record(corrections: [applied("clawed", "Claude", 1)]),
        ]
        let counts = LibraryUsage.correctionCounts(entries: [cloud, clawed], aliases: UsageAliases(), records: records)
        #expect(counts[cloud.id] == 2)
        #expect(counts[clawed.id] == 1)
    }

    @Test("What the engine heard matches the way the corrector does: case, spaces, hyphens")
    func heardIsMatchedLeniently() {
        let entry = DictionaryEntry.correction(hear: "cloud code", write: "Claude Code")
        let records = [
            record(corrections: [applied("CloudCode", "Claude Code", 1)]),
            record(corrections: [applied("cloud-code", "Claude Code", 1)]),
            record(corrections: [applied("Cloud Code", "Claude Code", 1)]),
        ]
        #expect(LibraryUsage.correctionCounts(entries: [entry], aliases: UsageAliases(), records: records)[entry.id] == 3)
    }

    @Test("Existing text-only history keeps its counts")
    func legacyHistoryStillCounts() {
        let entry = DictionaryEntry.correction(hear: "get hub", write: "GitHub")
        let snippet = Snippet(trigger: "My Address", expansion: "1 Main St", createdAt: now.addingTimeInterval(-100))
        let records = [
            record(corrections: [applied("get hub", "GitHub", 1)], snippets: ["My Address"]),
            record(snippets: ["my address"]),
        ]
        #expect(LibraryUsage.correctionCounts(entries: [entry], aliases: UsageAliases(), records: records)[entry.id] == 1)
        #expect(LibraryUsage.snippetCounts(snippets: [snippet], aliases: UsageAliases(), records: records)[snippet.id] == 2)
    }

    @Test("A replacement whose heard side changed falls back to what it writes, when that's unambiguous")
    func fallbackToWrite() {
        let edited = DictionaryEntry.correction(hear: "post gres", write: "Postgres")
        let records = [record(corrections: [applied("post gress", "Postgres", 1)])]
        #expect(LibraryUsage.correctionCounts(entries: [edited], aliases: UsageAliases(), records: records)[edited.id] == 1)

        // Two replacements write "Claude" and neither heard "clod": credit neither, not both.
        let cloud = DictionaryEntry.correction(hear: "cloud", write: "Claude")
        let clawed = DictionaryEntry.correction(hear: "clawed", write: "Claude")
        let ambiguous = [record(corrections: [applied("clod", "Claude", 1)])]
        #expect(LibraryUsage.correctionCounts(entries: [cloud, clawed], aliases: UsageAliases(), records: ambiguous).isEmpty)
    }

    @Test("A renamed snippet keeps the uses of its old trigger")
    func renamedSnippet() {
        var snippet = Snippet(trigger: "my link", expansion: "https://x", createdAt: now.addingTimeInterval(-100))
        var aliases = UsageAliases()
        aliases.renamed(
            owner: snippet.id.uuidString,
            from: LibraryUsage.snippetKey(trigger: "my link"),
            to: LibraryUsage.snippetKey(trigger: "calendly link"))
        snippet.trigger = "calendly link"
        let records = [record(snippets: ["my link"]), record(snippets: ["calendly link"])]
        #expect(LibraryUsage.snippetCounts(snippets: [snippet], aliases: aliases, records: records)[snippet.id] == 2)
    }

    @Test("A renamed replacement keeps its history, under its new key")
    func renamedReplacement() {
        let oldKey = LibraryUsage.correctionKey(hear: "cloud", write: "Claud")
        let newKey = LibraryUsage.correctionKey(hear: "cloud", write: "Claude")
        var aliases = UsageAliases()
        aliases.renamed(owner: oldKey, from: oldKey, to: newKey, newOwner: newKey)
        #expect(aliases.formerKeys(of: newKey) == [oldKey])
        #expect(aliases.formerKeys(of: oldKey).isEmpty)

        let entry = DictionaryEntry.correction(hear: "cloud", write: "Claude")
        let other = DictionaryEntry.correction(hear: "clawed", write: "Claud")
        let records = [record(corrections: [applied("cloud", "Claud", 3)])]
        let counts = LibraryUsage.correctionCounts(entries: [entry, other], aliases: aliases, records: records)
        #expect(counts[entry.id] == 3)
        #expect(counts[other.id] == nil)
    }

    @Test("Renaming back to an earlier key drops it from the former keys")
    func renameBack() {
        var aliases = UsageAliases()
        aliases.renamed(owner: "x", from: "a", to: "b")
        aliases.renamed(owner: "x", from: "b", to: "a")
        #expect(aliases.formerKeys(of: "x") == ["b"])
        aliases.remove(owner: "x")
        #expect(aliases.former.isEmpty)
    }

    @Test("A new snippet reusing a deleted one's trigger doesn't inherit its old uses")
    func newSnippetStartsFresh() {
        let snippet = Snippet(trigger: "zoom link", expansion: "https://zoom", createdAt: now)
        let records = [
            record(snippets: ["zoom link"], at: now.addingTimeInterval(-3_600)),
            record(snippets: ["zoom link"], at: now.addingTimeInterval(60)),
        ]
        #expect(LibraryUsage.snippetCounts(snippets: [snippet], aliases: UsageAliases(), records: records)[snippet.id] == 1)
    }

    @Test("A use that names its item is counted by id")
    func byID() {
        let id = UUID()
        let item = LibraryUsage.Item(id: id, key: "new")
        let uses = [LibraryUsage.Use(id: id, key: "something else", date: now)]
        #expect(LibraryUsage.tally(uses, items: [item]) == [id: 1])
    }

    @Test("Aliases round-trip through their file")
    func aliasesPersist() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("usage.json")
        var aliases = UsageAliases()
        aliases.renamed(owner: "o", from: "a", to: "b")
        aliases.save(to: url)
        #expect(UsageAliases.load(from: url) == aliases)
        #expect(UsageAliases.load(from: directory.appendingPathComponent("missing.json")) == UsageAliases())
    }
}
