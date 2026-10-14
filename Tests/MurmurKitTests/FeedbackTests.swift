import Foundation
import MurmurDictionary
import Testing
@testable import MurmurKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func note(
    _ text: String = "The dictionary turned board into BTAR again.",
    raw: String? = nil,
    minutesAgo: Double = 0,
    dictations: [HistoryRecord] = []
) -> FeedbackNote {
    FeedbackNote(
        createdAt: now.addingTimeInterval(-minutesAgo * 60),
        text: text,
        rawText: raw ?? text,
        audioDuration: 4.2,
        appVersion: "Version 1.0.0 (1)",
        commit: "d0d0221",
        system: "macOS Version 26.1 (Build 25B78)",
        frontmostApp: "Slack",
        frontmostBundleID: "com.tinyspeck.slackmacgap",
        setup: [.init("Engine", "Parakeet Ultra"), .init("Polish", "Off")],
        recentDictations: dictations
    )
}

private func dictation(_ final: String, raw: String, minutesAgo: Double, outcome: DictationOutcome = .inserted) -> HistoryRecord {
    HistoryRecord(
        createdAt: now.addingTimeInterval(-minutesAgo * 60),
        context: AppContext(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", category: .work),
        engine: "Parakeet Ultra",
        rawText: raw,
        finalText: final,
        corrections: [AppliedCorrection(from: "board", to: "BTAR", count: 2)],
        timings: DictationTimings(transcribeMs: 120, polishMs: 0, totalMs: 180),
        outcome: outcome
    )
}

@Suite("Feedback issue")
struct FeedbackIssueTests {
    @Test("The title is the note's first sentence")
    func titleIsFirstSentence() {
        #expect(FeedbackIssue.title(for: note("The dictionary turned board into BTAR again. It did it twice."))
            == "The dictionary turned board into BTAR again.")
    }

    @Test("A long title is cut at a word, with an ellipsis")
    func longTitle() {
        let text = String(repeating: "word ", count: 40)
        let title = FeedbackIssue.title(for: note(text))
        #expect(title.count <= 72)
        #expect(title.hasSuffix("word…"))
    }

    @Test("A note with no words still gets a title")
    func emptyTitle() {
        #expect(FeedbackIssue.title(for: note("  ")) == "Feedback (no words heard)")
    }

    @Test("The body quotes the note, lists the build and ends with its marker")
    func body() {
        let n = note()
        let body = FeedbackIssue.body(for: n, timeZone: TimeZone(identifier: "UTC")!)
        #expect(body.hasPrefix("> The dictionary turned board into BTAR again."))
        #expect(body.contains("| Build | Version 1.0.0 (1) · commit `d0d0221` |"))
        #expect(body.contains("| In | Slack (`com.tinyspeck.slackmacgap`) |"))
        #expect(body.contains("| Engine | Parakeet Ultra |"))
        #expect(body.contains("| Said | 2026-09-21 14:13:20 "))
        #expect(body.hasSuffix(FeedbackIssue.marker(for: n.id)))
        #expect(!body.contains("### Last dictation"))
    }

    @Test("What the engine heard is shown only when cleanup changed it")
    func heardAs() {
        #expect(!FeedbackIssue.body(for: note("Make it faster.", raw: "make it faster")).contains("Heard as"))
        #expect(FeedbackIssue.body(for: note("Make it faster.", raw: "um make it uh faster")).contains("Heard as: um make it uh faster"))
    }

    @Test("The last dictation shows what was heard, typed and replaced; earlier ones fold away")
    func dictations() {
        let n = note(dictations: [
            dictation("Write it on the BTAR.", raw: "Write it on the board.", minutesAgo: 1),
            dictation("Second.", raw: "Second.", minutesAgo: 2),
        ])
        let body = FeedbackIssue.body(for: n)
        #expect(body.contains("### Last dictation"))
        #expect(body.contains("> Write it on the board."))
        #expect(body.contains("> Write it on the BTAR."))
        #expect(body.contains("`board` → `BTAR` ×2"))
        #expect(body.contains("<details><summary>Earlier dictations (1)</summary>"))
    }

    @Test("Table cells can't be broken by the text in them")
    func tableEscaping() {
        #expect(FeedbackIssue.row("In", "a|b\nc") == "| In | a\\|b c |")
    }
}

@Suite("Feedback note")
struct FeedbackNoteTests {
    @Test("Recent dictations: the newest three from the past hour, with text or a failure")
    func recentDictations() {
        let records = [
            dictation("one", raw: "one", minutesAgo: 1),
            dictation("", raw: "", minutesAgo: 2, outcome: .cancelled),
            dictation("", raw: "", minutesAgo: 3, outcome: .failed),
            dictation("two", raw: "two", minutesAgo: 4),
            dictation("three", raw: "three", minutesAgo: 5),
            dictation("old", raw: "old", minutesAgo: 90),
        ]
        let picked = FeedbackNote.recentDictations(from: records, now: now)
        #expect(picked.map(\.finalText) == ["one", "", "two"])
        #expect(picked[1].outcome == .failed)
    }

    @Test("A note without words has nothing to send")
    func hasWords() {
        #expect(note().hasWords)
        #expect(!note(" \n").hasWords)
    }
}

@Suite("GitHub issues")
struct GitHubIssueTests {
    @Test("Repositories are read from owner/name or a web address", arguments: [
        "futureLevi/birdtown-flow-feedback",
        " futureLevi/birdtown-flow-feedback ",
        "https://github.com/futureLevi/birdtown-flow-feedback",
        "https://github.com/futureLevi/birdtown-flow-feedback/",
        "github.com/futureLevi/birdtown-flow-feedback.git",
        "git@github.com:futureLevi/birdtown-flow-feedback.git",
    ])
    func repository(_ text: String) {
        #expect(GitHubRepository(text)?.description == "futureLevi/birdtown-flow-feedback")
    }

    @Test("Anything else isn't a repository", arguments: ["", "birdtown", "a/b/c", "/name", "owner/", "own er/name"])
    func notARepository(_ text: String) {
        #expect(GitHubRepository(text) == nil)
    }

    @Test("The request posts the issue with the token and the label")
    func request() throws {
        let client = GitHubIssueClient(repository: GitHubRepository("futureLevi/feedback")!, token: "gho_abc")
        let request = try client.makeRequest(title: "Title", body: "Body", labels: ["feedback"])
        #expect(request.url?.absoluteString == "https://api.github.com/repos/futureLevi/feedback/issues")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gho_abc")
        let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(json?["title"] as? String == "Title")
        #expect(json?["labels"] as? [String] == ["feedback"])

        let unlabelled = try client.makeRequest(title: "Title", body: "Body", labels: [])
        let plain = try JSONSerialization.jsonObject(with: unlabelled.httpBody ?? Data()) as? [String: Any]
        #expect(plain?["labels"] == nil)
    }

    @Test("A created issue gives its number and address")
    func created() throws {
        let data = Data(#"{"number": 7, "html_url": "https://github.com/o/r/issues/7", "title": "x"}"#.utf8)
        #expect(try GitHubIssueClient.parseCreated(data: data, status: 201)
            == .init(number: 7, url: "https://github.com/o/r/issues/7"))
    }

    @Test("Failures say what to fix")
    func failures() {
        #expect(throws: FeedbackSendError.unauthorized) {
            try GitHubIssueClient.parseCreated(data: Data(#"{"message":"Bad credentials"}"#.utf8), status: 401)
        }
        #expect(throws: FeedbackSendError.repositoryNotFound) {
            try GitHubIssueClient.parseCreated(data: Data(#"{"message":"Not Found"}"#.utf8), status: 404)
        }
        #expect(throws: FeedbackSendError.rejected(status: 422, message: "Validation Failed")) {
            try GitHubIssueClient.parseCreated(data: Data(#"{"message":"Validation Failed"}"#.utf8), status: 422)
        }
    }

    @Test("Only a connection problem or a busy GitHub is worth retrying on its own")
    func transient() {
        #expect(FeedbackSendError.offline("The Internet connection appears to be offline.").isTransient)
        #expect(FeedbackSendError.rejected(status: 502, message: "Bad Gateway").isTransient)
        #expect(!FeedbackSendError.unauthorized.isTransient)
        #expect(!FeedbackSendError.rejected(status: 422, message: "Validation Failed").isTransient)
    }
}

@Suite("Feedback outbox")
@MainActor
struct FeedbackOutboxTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("feedback-tests-\(UUID().uuidString)")
    }

    @Test("Notes survive a relaunch, delivery state and all")
    func roundTrip() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = FeedbackOutbox(directory: directory)
        var sent = note("Sent one.", minutesAgo: 2, dictations: [dictation("Hi.", raw: "hi", minutesAgo: 3)])
        sent.delivery = .init(issueNumber: 3, issueURL: "https://github.com/o/r/issues/3", attempts: 1)
        #expect(outbox.save(sent))
        #expect(outbox.save(note("Waiting one.", minutesAgo: 1)))

        let reloaded = FeedbackOutbox(directory: directory)
        #expect(reloaded.notes.map(\.text) == ["Waiting one.", "Sent one."])
        #expect(reloaded.notes.last == sent)
    }

    @Test("Waiting notes go oldest first; sent ones and ones without words don't")
    func pending() {
        let outbox = FeedbackOutbox(previewNotes: [])
        var sent = note("Sent.", minutesAgo: 3)
        sent.delivery.issueURL = "https://github.com/o/r/issues/1"
        outbox.save(sent)
        outbox.save(note("Older.", minutesAgo: 2))
        outbox.save(note("", minutesAgo: 1.5))
        outbox.save(note("Newer.", minutesAgo: 1))
        #expect(outbox.pending.map(\.text) == ["Older.", "Newer."])
    }

    @Test("Saving a note again replaces it")
    func replace() {
        let outbox = FeedbackOutbox(previewNotes: [])
        var n = note()
        outbox.save(n)
        n.delivery.lastError = "Couldn't reach GitHub"
        outbox.save(n)
        #expect(outbox.notes.count == 1)
        #expect(outbox.note(id: n.id)?.delivery.lastError == "Couldn't reach GitHub")
    }

    @Test("Deleting takes the note and its recording")
    func delete() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = FeedbackOutbox(directory: directory)
        let n = note()
        outbox.save(n)
        try Data([0, 1]).write(to: outbox.audioURL(for: n.id))
        outbox.delete(id: n.id)
        #expect(outbox.notes.isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).isEmpty)
    }
}

@Suite("Feedback shortcut")
struct FeedbackShortcutTests {
    @Test("⌃⌥F is free to use, and can't take another action's shortcut")
    func shortcut() {
        #expect(ShortcutRules.check(.keys(.feedbackDefault), for: .feedback) == .accepted)
        let inUse: [ShortcutRole: KeyShortcut] = [.pasteLast: .keys(.pasteLastDefault), .feedback: .keys(.feedbackDefault)]
        #expect(!ShortcutRules.check(.keys(.pasteLastDefault), for: .feedback, inUse: inUse).isAccepted)
        #expect(!ShortcutRules.check(.keys(.feedbackDefault), for: .pasteLast, inUse: inUse).isAccepted)
    }
}
