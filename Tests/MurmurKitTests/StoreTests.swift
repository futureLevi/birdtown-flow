import Foundation
import Testing
@testable import MurmurKit

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("murmurkit-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func files(in directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
}

@Suite("HistoryStore")
@MainActor
struct HistoryStoreTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Persistence round trip")
    func roundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        let record = HistoryRecord(
            createdAt: now, context: AppContext(bundleID: "com.apple.mail", appName: "Mail", category: .email),
            style: .formal, engine: "Parakeet", rawText: "um hello", finalText: "Hello.", polishedBy: .anthropic,
            snippets: ["sig"], audioFileName: "a.wav", audioDuration: 2.5,
            timings: DictationTimings(transcribeMs: 120, polishMs: 300, totalMs: 450))
        store.add(record)
        store.flush()

        let reloaded = HistoryStore(directory: directory)
        #expect(reloaded.records == [record])
        #expect(reloaded.quarantinedFile == nil)
    }

    @Test("A corrupt file is copied aside, never overwritten")
    func corruptFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        try Data("{ not json".utf8).write(to: file)

        let store = HistoryStore(directory: directory)
        #expect(store.records.isEmpty)
        let aside = try #require(store.quarantinedFile)
        #expect(aside.lastPathComponent.hasPrefix("history.corrupt-"))
        #expect(try String(contentsOf: aside, encoding: .utf8) == "{ not json")

        store.add(HistoryRecord(createdAt: now, finalText: "New"))
        store.flush()
        #expect(try String(contentsOf: aside, encoding: .utf8) == "{ not json")
        #expect(HistoryStore(directory: directory).records.map(\.finalText) == ["New"])
    }

    @Test("Older files missing newer fields still load, and one bad record doesn't sink the rest")
    func legacyAndPartial() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = """
            [
              {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":"2026-09-01T10:00:00Z","finalText":"Old one","rawText":"old one"},
              {"id":"not-a-uuid","createdAt":"yesterday"},
              {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":"2026-09-02T10:00:00Z","finalText":"Newer","outcome":"copied","audioDuration":3}
            ]
            """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("history.json"))

        let store = HistoryStore(directory: directory)
        #expect(store.records.map(\.finalText) == ["Newer", "Old one"])
        #expect(store.records.first?.outcome == .copied)
        #expect(store.records.last?.outcome == .inserted)
        #expect(store.records.last?.corrections == [])
        // A record was unreadable, so the original is preserved before anything is saved over it.
        #expect(store.quarantinedFile != nil)
    }

    @Test("Retention drops old text and audio, but failed dictations keep their audio")
    func retention() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        func make(_ text: String, daysAgo: Double, outcome: DictationOutcome = .inserted) throws -> HistoryRecord {
            let id = UUID()
            let audio = store.newRecordingURL(for: id)
            try Data([0, 1, 2]).write(to: audio)
            return HistoryRecord(id: id, createdAt: now.addingTimeInterval(-daysAgo * 86_400), finalText: text,
                                 audioFileName: audio.lastPathComponent, outcome: outcome)
        }
        let fresh = try make("fresh", daysAgo: 1)
        let oldAudio = try make("old audio", daysAgo: 10)
        let failed = try make("failed", daysAgo: 11, outcome: .failed)
        let ancient = try make("ancient", daysAgo: 40)
        for record in [fresh, oldAudio, failed, ancient] { store.add(record) }

        store.applyRetention(textDays: 30, audioDays: 7, now: now)

        #expect(store.records.map(\.finalText) == ["fresh", "old audio", "failed"])
        #expect(store.audioURL(for: store.record(id: fresh.id)!) != nil)
        #expect(store.record(id: oldAudio.id)?.audioFileName == nil)
        #expect(!FileManager.default.fileExists(atPath: store.newRecordingURL(for: oldAudio.id).path))
        #expect(store.audioURL(for: store.record(id: failed.id)!) != nil)
        #expect(!FileManager.default.fileExists(atPath: store.newRecordingURL(for: ancient.id).path))
    }

    @Test("Search covers final text, raw text and app name, ignoring case and accents")
    func search() {
        let store = HistoryStore(previewRecords: [
            HistoryRecord(createdAt: now, rawText: "the cafe meeting", finalText: "The café meeting."),
            HistoryRecord(createdAt: now.addingTimeInterval(-60),
                          context: AppContext(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", category: .work),
                          rawText: "um ship it", finalText: "Ship it."),
        ])
        #expect(store.search("CAFE").map(\.finalText) == ["The café meeting."])
        #expect(store.search("slack").map(\.finalText) == ["Ship it."])
        #expect(store.search("um ship").map(\.finalText) == ["Ship it."])
        #expect(store.search("  ").count == 2)
        #expect(store.search("nothing like this").isEmpty)
    }

    @Test("latestWithText skips failures, cancellations and empty results")
    func latestWithText() {
        let store = HistoryStore(previewRecords: [
            HistoryRecord(createdAt: now, finalText: "Failed one", outcome: .failed),
            HistoryRecord(createdAt: now.addingTimeInterval(-1), finalText: "", outcome: .empty),
            HistoryRecord(createdAt: now.addingTimeInterval(-2), finalText: "Cancelled", outcome: .cancelled),
            HistoryRecord(createdAt: now.addingTimeInterval(-3), finalText: "Copied text", outcome: .copied),
            HistoryRecord(createdAt: now.addingTimeInterval(-4), finalText: "Older", outcome: .inserted),
        ])
        #expect(store.latestWithText?.finalText == "Copied text")
    }

    @Test("Grouped by day, newest first")
    func groupedByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.startOfDay(for: now)
        let records = [
            HistoryRecord(createdAt: day.addingTimeInterval(3_600), finalText: "a"),
            HistoryRecord(createdAt: day.addingTimeInterval(-3_600), finalText: "b"),
            HistoryRecord(createdAt: day.addingTimeInterval(7_200), finalText: "c"),
        ]
        let groups = HistoryStore.groupedByDay(records, calendar: calendar)
        #expect(groups.map(\.day) == [day, day.addingTimeInterval(-86_400)])
        #expect(groups.map { $0.records.map(\.finalText) } == [["c", "a"], ["b"]])
        #expect(HistoryStore.groupedByDay([], calendar: calendar).isEmpty)
    }

    @Test("Deleting removes records and their audio")
    func delete() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        let id = UUID()
        let audio = store.newRecordingURL(for: id)
        try Data([1]).write(to: audio)
        store.add(HistoryRecord(id: id, createdAt: now, finalText: "x", audioFileName: audio.lastPathComponent))
        store.delete(ids: [id])
        #expect(store.records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
    }
}

@Suite("SnippetStore")
@MainActor
struct SnippetStoreTests {
    @Test("Persistence round trip and conflicts")
    func roundTrip() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("snippets.json")
        let store = SnippetStore(fileURL: file)
        let snippet = Snippet(trigger: "My Calendly", expansion: "https://calendly.com/x", createdAt: Date(timeIntervalSince1970: 0))
        store.add(snippet)
        #expect(SnippetStore(fileURL: file).snippets == [snippet])
        #expect(store.hasConflict(trigger: " my calendly "))
        #expect(!store.hasConflict(trigger: "my calendly", excluding: snippet.id))
    }

    @Test("A corrupt file is copied aside before anything replaces it")
    func corrupt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("snippets.json")
        try Data("[{\"broken\":".utf8).write(to: file)
        let store = SnippetStore(fileURL: file)
        #expect(store.snippets.isEmpty)
        let aside = try #require(store.quarantinedFile)
        #expect(files(in: directory).contains(aside.lastPathComponent))
        store.add(Snippet(trigger: "a", expansion: "b"))
        #expect(try String(contentsOf: aside, encoding: .utf8) == "[{\"broken\":")
    }
}
