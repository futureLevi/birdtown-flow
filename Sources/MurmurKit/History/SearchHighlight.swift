import Foundation

/// Why a History record matched a search, and where, so the list can show the hit in
/// context the way Mail does. Matching is the same as `HistoryStore.search`: the trimmed
/// query as one phrase, ignoring case and diacritics.
public enum SearchHighlight {
    /// The parts of a record a search looks at.
    public enum Field: Sendable, Hashable {
        /// What was typed (`finalText`).
        case text
        /// What the engine heard (`rawText`), shown under Show Original.
        case heard
        /// The app it was dictated into.
        case app
    }

    /// Every part of `record` that `query` matches. Empty for a blank query.
    public static func fields(of record: HistoryRecord, matching query: String) -> Set<Field> {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        var fields: Set<Field> = []
        if contains(needle, in: record.finalText) { fields.insert(.text) }
        if contains(needle, in: record.rawText) { fields.insert(.heard) }
        if let app = record.context?.appName, contains(needle, in: app) { fields.insert(.app) }
        return fields
    }

    /// Every non-overlapping match of `query` in `text`, in order.
    public static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let match = text.range(of: needle, options: options, range: searchStart..<text.endIndex) {
            found.append(match)
            // An empty match can't happen with a non-empty needle, but never loop forever.
            searchStart = match.upperBound > match.lowerBound ? match.upperBound : text.index(after: match.lowerBound)
        }
        return found
    }

    /// What a collapsed row shows: the text itself, or, when the first match would fall past
    /// the `budget` characters the preview has room for, an excerpt that starts "…" a little
    /// before it, at a word boundary.
    public struct Preview: Equatable, Sendable {
        public var text: String
        public var ranges: [Range<String.Index>]
        /// Whether `text` starts part way through the original.
        public var isExcerpt: Bool

        public init(text: String, ranges: [Range<String.Index>], isExcerpt: Bool = false) {
            self.text = text
            self.ranges = ranges
            self.isExcerpt = isExcerpt
        }
    }

    public static func preview(of text: String, query: String, budget: Int, lead: Int = 40) -> Preview {
        let matches = ranges(of: query, in: text)
        guard let first = matches.first,
              text.distance(from: text.startIndex, to: first.upperBound) > budget
        else { return Preview(text: text, ranges: matches, isExcerpt: false) }

        // Back up `lead` characters, then forward to the start of a word.
        var start = text.index(first.lowerBound, offsetBy: -lead, limitedBy: text.startIndex) ?? text.startIndex
        if start > text.startIndex {
            while start < first.lowerBound, !text[text.index(before: start)].isWhitespace {
                start = text.index(after: start)
            }
        }
        guard start > text.startIndex else { return Preview(text: text, ranges: matches, isExcerpt: false) }
        let excerpt = "…" + String(text[start...].drop(while: \.isWhitespace))
        return Preview(text: excerpt, ranges: ranges(of: query, in: excerpt), isExcerpt: true)
    }

    private static var options: String.CompareOptions { [.caseInsensitive, .diacriticInsensitive] }

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contains(_ needle: String, in haystack: String) -> Bool {
        haystack.range(of: needle, options: options) != nil
    }
}
