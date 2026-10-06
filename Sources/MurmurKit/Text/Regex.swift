import Foundation

// Small regex helpers shared by the text pipeline and the polish guard.
//
// NSRegularExpression is used (rather than Swift Regex) because the dictionary layer already
// standardises on ICU semantics, and keeping one engine means one set of edge cases.

/// Compiles a constant pattern. Every pattern passed here is a literal exercised by the test
/// suite, so a compile failure is a programming error caught before shipping, not a runtime
/// condition to recover from.
func makeRegex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    } catch {
        preconditionFailure("Invalid built-in pattern \(pattern): \(error)")
    }
}

/// Letters, digits, apostrophes and hyphens glue a word together; a match fenced by these
/// lookarounds can never bite into a longer word ("um" in "umbrella", "er" in "error").
let wordFenceBefore = "(?<![\\p{L}\\p{N}'’\\-])"
let wordFenceAfter = "(?![\\p{L}\\p{N}'’\\-])"

extension NSRegularExpression {
    func replacingMatches(in text: String, template: String) -> String {
        stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: NSString(string: text).length), withTemplate: template)
    }

    /// Replaces each match with what `transform` returns; `nil` leaves that match untouched.
    func replacingMatches(
        in text: String,
        using transform: (_ match: NSTextCheckingResult, _ text: NSString) -> String?
    ) -> String {
        let ns = NSString(string: text)
        var output = ""
        var cursor = 0
        for match in matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let range = match.range
            output += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            output += transform(match, ns) ?? ns.substring(with: range)
            cursor = range.location + range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    func matches(_ text: String) -> Bool {
        firstMatch(in: text, range: NSRange(location: 0, length: NSString(string: text).length)) != nil
    }
}

extension NSTextCheckingResult {
    /// The text of capture group `index`, or `nil` when the group didn't participate.
    func group(_ index: Int, in text: NSString) -> String? {
        let range = range(at: index)
        return range.location == NSNotFound ? nil : text.substring(with: range)
    }
}
