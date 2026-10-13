import Foundation

/// A dictionary correction that changed a transcript, kept with the History entry.
public struct AppliedCorrection: Codable, Hashable, Sendable {
    /// The words as the engine wrote them, from the first place the rule changed something.
    public let from: String
    /// The dictionary's spelling that went in their place.
    public let to: String
    /// How many places in the transcript the rule changed.
    public let count: Int

    public init(from: String, to: String, count: Int) {
        self.from = from
        self.to = to
        self.count = count
    }
}

/// Applies the dictionary's corrections to a finished transcript.
///
/// Engine hints only make a spelling more likely. This is the step that makes it certain:
/// once the text is final, every enabled correction is applied by plain text matching, with
/// the same result every time.
///
/// What counts as a match for a trigger:
///
/// - Letter case is ignored, and an accented letter matches however it was encoded, because
///   the trigger and the text are both converted to the composed Unicode form (NFC) first.
/// - Only whole words match. There can't be a letter or digit directly before or after the
///   match, so a "bird town" rule leaves "birdtowns" and "lovebird town" alone.
/// - The words of a trigger can be joined by any run of spaces and hyphens, or by nothing,
///   because engines produce all of those: "bird town" also matches "Birdtown", "bird-town"
///   and "bird  town".
///
/// How rules interact:
///
/// - Longer triggers are tried first, so "flow lab" gets its say before "flow" does.
/// - Every rule looks at the transcript as the engine wrote it, in a single pass. Once a rule
///   has matched some text, no other rule can match any part of it, so one rule never
///   rewrites what another one wrote.
/// - A match that already reads exactly the way the rule would write it is left as it is and
///   isn't reported, so History only credits the dictionary with real fixes.
public struct DictionaryCorrector: Sendable {
    /// One enabled correction, compiled.
    private struct CompiledRule: Sendable {
        let pattern: NSRegularExpression
        let replacement: String
    }

    /// A stretch of the transcript, in UTF-16 units, and what goes there instead.
    private struct Splice {
        let range: NSRange
        let text: String
    }

    /// Longest trigger first.
    private let rules: [CompiledRule]

    public init(entries: [DictionaryEntry]) {
        let usable = entries.enumerated().filter {
            $0.element.isEnabled && $0.element.kind == .correction
                && !$0.element.hear.trimmed.isEmpty
        }
        // Ordering by trigger length is what lets a longer rule claim its text before a
        // shorter one that overlaps it. Equal lengths keep the order the entries came in.
        let longestFirst = usable.sorted { lhs, rhs in
            let lhsLength = lhs.element.hear.count
            let rhsLength = rhs.element.hear.count
            return lhsLength == rhsLength ? lhs.offset < rhs.offset : lhsLength > rhsLength
        }
        rules = longestFirst.compactMap { candidate in
            guard let pattern = Self.pattern(for: candidate.element.hear) else { return nil }
            return CompiledRule(pattern: pattern, replacement: candidate.element.write)
        }
    }

    /// True when there are no enabled corrections, so `apply(to:)` would change nothing.
    public var isEmpty: Bool { rules.isEmpty }

    /// Runs every rule over `text`.
    ///
    /// - Returns: the corrected text, and one `AppliedCorrection` for each rule that changed
    ///   at least one place.
    public func apply(to text: String) -> (text: String, applied: [AppliedCorrection]) {
        if rules.isEmpty || text.isEmpty { return (text, []) }

        // Text can arrive decomposed (a plain letter followed by a combining accent), from a
        // file read or another app. The patterns are composed, so the text has to be too, or
        // an accented trigger would never match.
        let heard = text.precomposedStringWithCanonicalMapping
        let units = NSString(string: heard)
        let whole = NSRange(location: 0, length: units.length)

        // UTF-16 offsets that some rule has already matched.
        var claimed = IndexSet()
        var splices: [Splice] = []
        var report: [AppliedCorrection] = []

        for rule in rules {
            var firstChanged: String?
            var changes = 0

            for match in rule.pattern.matches(in: heard, range: whole) {
                let span = match.range.location ..< match.range.location + match.range.length
                if claimed.intersects(integersIn: span) { continue }
                claimed.insert(integersIn: span)

                let found = units.substring(with: match.range)
                // Swift compares strings by canonical equivalence, so this also holds when
                // the rule's spelling was typed in decomposed form.
                if found == rule.replacement { continue }

                splices.append(Splice(range: match.range, text: rule.replacement))
                changes += 1
                if firstChanged == nil { firstChanged = found }
            }

            if let firstChanged {
                report.append(AppliedCorrection(from: firstChanged, to: rule.replacement, count: changes))
            }
        }

        return (Self.splice(splices, into: units), report)
    }

    /// `text` with each splice's range replaced by its text. Splices never overlap.
    private static func splice(_ splices: [Splice], into text: NSString) -> String {
        var output = ""
        var cursor = 0
        for splice in splices.sorted(by: { $0.range.location < $1.range.location }) {
            output += text.substring(with: NSRange(location: cursor, length: splice.range.location - cursor))
            output += splice.text
            cursor = splice.range.location + splice.range.length
        }
        output += text.substring(from: cursor)
        return output
    }

    /// The regular expression for one trigger, or nil when there's nothing to match.
    ///
    /// The trigger is split into words at spaces, tabs and hyphens. Each word is escaped, so
    /// punctuation in it is matched literally, and the words are joined by `[\s\-]*`: any
    /// run of whitespace and hyphens, including none.
    ///
    /// Both ends are guarded by lookarounds that forbid a letter or digit. `\b` isn't strict
    /// enough: it counts a hyphen or apostrophe as the edge of a word, which would let a rule
    /// fire on part of a longer word.
    private static func pattern(for trigger: String) -> NSRegularExpression? {
        // Composed, like the text in `apply(to:)`: a trigger typed in the app and one read
        // back from the dictionary file aren't always in the same form.
        let words = trigger.precomposedStringWithCanonicalMapping.trimmed
            .split(whereSeparator: { " \t-".contains($0) })
        if words.isEmpty { return nil }

        let gap = #"[\s\-]*"#
        let wordCharacter = #"[\p{L}\p{N}]"#
        let body = words
            .map { word in NSRegularExpression.escapedPattern(for: String(word)) }
            .joined(separator: gap)
        return try? NSRegularExpression(
            pattern: "(?<!\(wordCharacter))\(body)(?!\(wordCharacter))", options: .caseInsensitive)
    }
}

// MARK: - Engine hints

extension DictionaryCorrector {
    /// The most phrases handed to the speech engine as hints.
    ///
    /// More isn't better. With a long hint list, the engine starts writing hint words nobody
    /// said when the audio is quiet or unclear, which is worse than an occasional misspelling.
    public static let biasLimit = 40

    /// The spellings to give the speech engine as hints, in the order of `entries`.
    ///
    /// Takes the `write` side of every enabled entry, trimmed. Blank phrases are skipped, as is
    /// any phrase that only differs in case from one already taken, and the list stops at
    /// `biasLimit`.
    public static func biasPhrases(from entries: [DictionaryEntry]) -> [String] {
        var hints: [String] = []
        var taken = Set<String>()

        for entry in entries {
            guard hints.count < biasLimit else { break }
            guard entry.isEnabled else { continue }
            let hint = entry.write.trimmed
            if hint.isEmpty || !taken.insert(hint.lowercased()).inserted { continue }
            hints.append(hint)
        }

        return hints
    }
}
