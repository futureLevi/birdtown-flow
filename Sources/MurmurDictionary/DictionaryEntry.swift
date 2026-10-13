import Foundation

/// A single line of the user's dictionary.
///
/// An entry is either a spelling to teach the engine or a fix to apply afterwards:
///
/// - A **term** is a word or name the user wants spelled their way, like "Birdtown" or
///   "Parakeet". It only steers the speech engine; there's nothing to rewrite.
/// - A **correction** says "if the transcript has `hear`, put `write` there instead", like
///   "bird town" becoming "Birdtown". The `write` side steers the engine too.
///
/// The property names are the keys in the saved file, so renaming one breaks every
/// existing dictionary.
public struct DictionaryEntry: Identifiable, Codable, Hashable, Sendable {
    /// Stored as its raw value; don't rename the cases.
    public enum Kind: String, Codable, Sendable {
        case term, correction
    }

    public var id: UUID
    public var kind: Kind

    /// The spelling the user wants to see. For a term it's the whole entry; for a correction
    /// it's the replacement. Engine hints are always taken from this side.
    public var write: String

    /// What the engine gets wrong, for corrections. Terms leave it empty.
    public var hear: String

    /// Switched-off entries stay in the file so they can be turned back on, but neither
    /// steer the engine nor rewrite anything.
    public var isEnabled: Bool

    public init(id: UUID = UUID(), kind: Kind, write: String, hear: String = "", isEnabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.hear = hear
        self.write = write
        self.isEnabled = isEnabled
    }

    /// A term entry for `word`.
    public static func term(_ word: String) -> DictionaryEntry {
        Self(kind: .term, write: word)
    }

    /// A correction entry that puts `write` wherever `hear` turns up.
    public static func correction(hear: String, write: String) -> DictionaryEntry {
        Self(kind: .correction, write: write, hear: hear)
    }

    /// The entry as one line of the plain-text dictionary file: `hear -> write` for a
    /// correction, the bare word for a term, and a `# off: ` prefix when it's switched off.
    public var fileLine: String {
        let line: String
        switch kind {
        case .term: line = write
        case .correction: line = "\(hear) -> \(write)"
        }
        return isEnabled ? line : "# off: " + line
    }

    /// `parsed` with each entry's id taken from an identical entry in `existing`, where there
    /// is one, so re-reading the file doesn't give every unchanged entry a fresh identity.
    ///
    /// Matched on content (kind, hear, write, isEnabled), each existing id used at most once —
    /// duplicate lines are legal, and two entries sharing an id would break id-based edits.
    /// Unmatched entries keep the id they came with. Content is never changed.
    public static func carryingIDs(
        from existing: [DictionaryEntry], into parsed: [DictionaryEntry]
    ) -> [DictionaryEntry] {
        struct Content: Hashable {
            let kind: DictionaryEntry.Kind
            let hear: String
            let write: String
            let isEnabled: Bool

            init(_ entry: DictionaryEntry) {
                kind = entry.kind
                hear = entry.hear
                write = entry.write
                isEnabled = entry.isEnabled
            }
        }

        // Unused ids per content, oldest first, so duplicates map back in their original order.
        var available: [Content: [UUID]] = [:]
        for entry in existing {
            available[Content(entry), default: []].append(entry.id)
        }

        return parsed.map { entry in
            let key = Content(entry)
            guard var ids = available[key], !ids.isEmpty else { return entry }
            var carried = entry
            carried.id = ids.removeFirst()
            available[key] = ids
            return carried
        }
    }
}

/// A heads-up that a correction might rewrite text the user didn't mean it to.
///
/// Shown next to the entry in the Dictionary screen. It's advice only: saving still works,
/// because sometimes rewriting an everyday word is exactly what the user wants.
public struct DictionaryWarning: Identifiable, Sendable {
    public let message: String

    public var id: String { message }

    /// Everyday words that would fire all the time as a one-word trigger: the most frequent
    /// English words, plus the ones people say constantly while talking about software.
    /// It's meant to catch the obvious mistakes, not to be complete.
    private static let everydayWords: Set<String> = [
        // Function words.
        "a", "about", "after", "again", "all", "also", "am", "an", "and", "any", "are", "around",
        "as", "at", "be", "because", "been", "before", "but", "by", "can", "could", "did", "do",
        "does", "down", "each", "even", "every", "few", "for", "from", "had", "has", "have", "he",
        "her", "here", "him", "his", "how", "i", "if", "in", "into", "is", "it", "its", "just",
        "may", "me", "might", "more", "most", "must", "my", "never", "no", "nor", "not", "now",
        "of", "off", "on", "once", "only", "or", "other", "our", "out", "over", "same", "she",
        "should", "so", "some", "still", "such", "than", "that", "the", "their", "them", "then",
        "there", "these", "they", "this", "those", "to", "too", "under", "up", "us", "very", "was",
        "we", "were", "what", "when", "where", "which", "while", "who", "why", "will", "with",
        "without", "would", "yes", "yet", "you", "your",
        // Everyday verbs, nouns and adjectives.
        "bad", "big", "bird", "book", "build", "call", "come", "day", "done", "end", "fine",
        "flow", "get", "give", "go", "good", "great", "help", "home", "keep", "know", "last",
        "let", "like", "long", "look", "lot", "made", "make", "mean", "move", "need", "new",
        "next", "note", "old", "real", "really", "right", "said", "say", "see", "send", "show",
        "start", "stop", "sure", "talk", "tell", "thanks", "thing", "think", "time", "today",
        "town", "try", "turn", "use", "want", "way", "week", "well", "word", "work", "write",
        "year",
        // Words that come up all the time when talking about software.
        "app", "branch", "bug", "button", "change", "chat", "click", "copy", "data", "deploy",
        "doc", "draft", "email", "error", "field", "file", "fix", "folder", "link", "log", "mail",
        "merge", "model", "page", "paste", "push", "save", "screen", "server", "test", "text",
        "type", "update", "user", "view", "voice", "window",
    ]

    /// Warnings for `entry`, or none when it looks safe.
    public static func check(_ entry: DictionaryEntry) -> [DictionaryWarning] {
        // Terms are never matched against the transcript, so they can't misfire.
        if entry.kind == .term { return [] }

        let trigger = entry.hear.trimmed
        if trigger.isEmpty { return [] }

        var found: [DictionaryWarning] = []
        let words = trigger.lowercased().split(whereSeparator: { " -".contains($0) })

        // A phrase of two or more words is specific enough; only a lone word gets checked.
        if words.count == 1 {
            let word = String(words[0])
            if everydayWords.contains(word) {
                found.append(DictionaryWarning(
                    message: "“\(trigger)” is an everyday word, so this changes it every time you "
                        + "say it. A longer phrase is safer."
                ))
            } else if word.count <= 3 {
                found.append(DictionaryWarning(
                    message: "“\(trigger)” is only a few letters long and may turn up where you "
                        + "don't expect it. A longer phrase is safer."
                ))
            }
        }

        if entry.write.trimmed.caseInsensitiveCompare(trigger) == .orderedSame {
            found.append(DictionaryWarning(
                message: "This writes back the same word it listens for, so it won't change anything."
            ))
        }

        return found
    }
}

extension String {
    /// The string without whitespace or line breaks at either end.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
