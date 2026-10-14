import Foundation
import MurmurDictionary

/// A note about Birdtown Flow itself, said with the feedback shortcut instead of typed
/// anywhere: "the dictionary turned board into BTAR again".
///
/// It carries what's needed to act on it without asking: the build, where the person was, how
/// dictation is set up, and the last few dictations, since a note is usually about the one
/// that just went wrong. `FeedbackIssue` turns it into a GitHub issue; `FeedbackOutbox` keeps
/// it on disk until that issue exists.
public struct FeedbackNote: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var createdAt: Date
    /// What was said, after filler words are taken out. Never polished: the words are the point.
    public var text: String
    /// Exactly what the speech engine returned.
    public var rawText: String
    /// The recording, next to the note in the outbox. `nil` if it couldn't be written.
    public var audioFileName: String?
    public var audioDuration: Double
    /// "Version 1.0.0 (1)".
    public var appVersion: String
    /// The commit the build was made from, when the bundle records it.
    public var commit: String?
    /// "macOS 26.1".
    public var system: String
    /// The app that was in front when the shortcut was pressed.
    public var frontmostApp: String?
    public var frontmostBundleID: String?
    /// How dictation is set up right now: engine, polish, boosting… in display order.
    public var setup: [Detail]
    /// The most recent dictations, newest first, as History has them.
    public var recentDictations: [HistoryRecord]
    public var delivery: Delivery

    public struct Detail: Codable, Hashable, Sendable {
        public var label: String
        public var value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    /// Where the note has got to. A note is sent once it has an issue.
    public struct Delivery: Codable, Hashable, Sendable {
        public var issueNumber: Int?
        public var issueURL: String?
        public var attempts: Int
        public var lastAttempt: Date?
        /// Why the last attempt failed, as Settings shows it.
        public var lastError: String?

        public init(issueNumber: Int? = nil, issueURL: String? = nil, attempts: Int = 0,
                    lastAttempt: Date? = nil, lastError: String? = nil) {
            self.issueNumber = issueNumber
            self.issueURL = issueURL
            self.attempts = attempts
            self.lastAttempt = lastAttempt
            self.lastError = lastError
        }

        public var isSent: Bool { issueURL != nil }
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String,
        rawText: String,
        audioFileName: String? = nil,
        audioDuration: Double = 0,
        appVersion: String,
        commit: String? = nil,
        system: String,
        frontmostApp: String? = nil,
        frontmostBundleID: String? = nil,
        setup: [Detail] = [],
        recentDictations: [HistoryRecord] = [],
        delivery: Delivery = Delivery()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.rawText = rawText
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.appVersion = appVersion
        self.commit = commit
        self.system = system
        self.frontmostApp = frontmostApp
        self.frontmostBundleID = frontmostBundleID
        self.setup = setup
        self.recentDictations = recentDictations
        self.delivery = delivery
    }

    /// Whether there's anything to file: a recording that couldn't be transcribed has no words.
    public var hasWords: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How many recent dictations a note carries.
    public static let recentDictationLimit = 3

    /// The dictations worth attaching from History's records (newest first): ones with text,
    /// or ones that failed, since "that one didn't work" is feedback too. Nothing older than
    /// `maxAge`, so a note on a fresh morning doesn't drag in yesterday's work.
    public static func recentDictations(
        from records: [HistoryRecord], now: Date = Date(), maxAge: TimeInterval = 60 * 60
    ) -> [HistoryRecord] {
        Array(
            records
                .filter { now.timeIntervalSince($0.createdAt) <= maxAge }
                .filter { $0.hasText || $0.outcome == .failed || $0.outcome == .empty }
                .prefix(recentDictationLimit)
        )
    }
}

// MARK: - The issue

/// The GitHub issue a feedback note becomes.
public enum FeedbackIssue {
    /// Every feedback issue gets it, so the routine that files them in the backlog can find
    /// them among anything else in the repository.
    public static let label = "feedback"

    /// Ends every body, so a note is never filed twice and the routine can match an issue to
    /// its note.
    public static func marker(for id: UUID) -> String {
        "<!-- birdtown-feedback id=\(id.uuidString) -->"
    }

    /// The note's first sentence, cut at a word to fit a list of issues.
    public static func title(for note: FeedbackNote, maxLength: Int = 72) -> String {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Feedback (no words heard)" }
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        var sentence = firstLine
        if let end = firstLine.firstIndex(where: { ".!?".contains($0) }),
           firstLine.distance(from: firstLine.startIndex, to: end) >= 12 {
            sentence = String(firstLine[...end])
        }
        guard sentence.count > maxLength else { return sentence }
        let cut = sentence.prefix(maxLength - 1)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }

    public static func body(for note: FeedbackNote, timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        lines.append(quoted(note.text.isEmpty ? "(no words heard)" : note.text))
        if !note.rawText.isEmpty, normalized(note.rawText) != normalized(note.text) {
            lines.append("")
            lines.append("<sub>Heard as: \(inline(note.rawText))</sub>")
        }

        lines.append("")
        lines.append("| | |")
        lines.append("|---|---|")
        lines.append(row("Said", stamp(note.createdAt, timeZone: timeZone)
            + String(format: " · %.1f s", note.audioDuration)))
        lines.append(row("Build", [note.appVersion, note.commit.map { "commit `\($0)`" }]
            .compactMap { $0 }.joined(separator: " · ")))
        lines.append(row("System", note.system))
        if let app = note.frontmostApp ?? note.frontmostBundleID {
            let bundle = note.frontmostApp != nil ? note.frontmostBundleID.map { " (`\($0)`)" } ?? "" : ""
            lines.append(row("In", app + bundle))
        }
        for detail in note.setup {
            lines.append(row(detail.label, detail.value))
        }

        if let last = note.recentDictations.first {
            lines.append("")
            lines.append("### Last dictation")
            lines.append("")
            lines.append(contentsOf: dictation(last, timeZone: timeZone))
            let earlier = note.recentDictations.dropFirst()
            if !earlier.isEmpty {
                lines.append("")
                lines.append("<details><summary>Earlier dictations (\(earlier.count))</summary>")
                for record in earlier {
                    lines.append("")
                    lines.append(contentsOf: dictation(record, timeZone: timeZone))
                }
                lines.append("")
                lines.append("</details>")
            }
        }

        lines.append("")
        lines.append(marker(for: note.id))
        return lines.joined(separator: "\n")
    }

    /// One dictation: when and where, then what was heard, what was typed and what changed it.
    static func dictation(_ record: HistoryRecord, timeZone: TimeZone) -> [String] {
        var facts = [stamp(record.createdAt, timeZone: timeZone)]
        if let app = record.context?.appName { facts.append(app) }
        if !record.engine.isEmpty { facts.append(record.engine) }
        facts.append(record.outcome.rawValue)
        if let polishedBy = record.polishedBy {
            facts.append("polished by \(polishedBy.title)"
                + (record.polishConfiguration.map { " (\($0))" } ?? ""))
        }
        if record.timings.totalMs > 0 { facts.append("\(record.timings.totalMs) ms") }

        var lines = ["**" + facts.joined(separator: " · ") + "**", ""]
        lines.append("Heard:")
        lines.append(quoted(record.rawText.isEmpty ? "(nothing)" : record.rawText))
        lines.append("")
        lines.append("Typed:")
        lines.append(quoted(record.finalText.isEmpty ? "(nothing)" : record.finalText))
        if !record.corrections.isEmpty {
            lines.append("")
            let changes = record.corrections.map { correction in
                "`\(correction.from)` → `\(correction.to)`" + (correction.count > 1 ? " ×\(correction.count)" : "")
            }
            lines.append("Replacements: " + changes.joined(separator: ", "))
        }
        if let error = record.errorMessage, !error.isEmpty {
            lines.append("")
            lines.append("Note: \(inline(error))")
        }
        return lines
    }

    // MARK: Markdown

    /// A block quote, every line of it, so the person's words read as theirs.
    static func quoted(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
    }

    /// Safe inside a table cell or a single line: no line breaks, no column bars.
    static func inline(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    static func row(_ label: String, _ value: String) -> String {
        "| \(inline(label)) | \(inline(value)) |"
    }

    static func stamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
