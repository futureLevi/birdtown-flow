import Foundation
import MurmurDictionary

// CONTRACT — owned by the MurmurKit agent. Signatures here are what the app calls.
//
// Order of operations for one dictation:
//
//   raw engine text
//     → TextPipeline.prepare        fillers, stutters, spoken commands ("new line")
//     → [optional AI polish]        app-side, see PolishService
//     → TextPipeline.finalize       snippets, style rules, then dictionary corrections
//     → inserted
//
// `finalize` runs even when polish succeeded, so the dictionary's guarantees hold no matter
// what the model wrote.

public struct PipelineOptions: Sendable {
    /// Removes filler sounds and also collapses stutters and cut-off restarts — all three
    /// are hesitation, and someone who wants a verbatim transcript wants all three kept.
    public var removeFillers: Bool
    public var spokenCommands: Bool

    public init(removeFillers: Bool = true, spokenCommands: Bool = true) {
        self.removeFillers = removeFillers
        self.spokenCommands = spokenCommands
    }
}

public struct PipelineResult: Sendable, Equatable {
    public var text: String
    public var corrections: [AppliedCorrection]
    /// Triggers of the snippets that expanded.
    public var snippets: [String]

    public init(text: String, corrections: [AppliedCorrection] = [], snippets: [String] = []) {
        self.text = text
        self.corrections = corrections
        self.snippets = snippets
    }
}

public enum TextPipeline {
    /// Filler sounds removed by `prepare`, for the UI to describe. Elongated forms ("ummm",
    /// "hmmm") count too; capitalised acronyms ("ER") and "mm" after a number never do.
    public static let fillerWords = ["um", "uh", "erm", "uhm", "umm", "uhh", "er", "ah", "hmm", "mm"]

    /// Words whose immediate repetition ("the the", "I I") is collapsed by `prepare`.
    public static var stutterWords: [String] { Cleanup.stutterWords }

    /// Casual style drops the final period only from a single sentence of at most this many words.
    public static let casualPeriodWordLimit = 15

    /// Deterministic cleanup before any AI polish.
    public static func prepare(_ raw: String, options: PipelineOptions = PipelineOptions()) -> String {
        var text = Cleanup.tidy(raw.precomposedStringWithCanonicalMapping)
        guard !text.isEmpty else { return "" }
        if options.removeFillers {
            text = Cleanup.removeFillers(text)
            text = Cleanup.collapseStutters(text)
        }
        if options.spokenCommands {
            text = Cleanup.applySpokenCommands(text)
        }
        return Cleanup.tidy(text)
    }

    /// Snippets, then the writing style's casing/punctuation rules, then dictionary corrections.
    ///
    /// - Parameter vocabulary: the dictionary's correct spellings. Very casual style lowercases
    ///   everything else, so these are what keep "Anthropic" from becoming "anthropic".
    public static func finalize(
        _ text: String,
        style: WritingStyle,
        corrector: DictionaryCorrector,
        snippets: [Snippet],
        vocabulary: [String] = []
    ) -> PipelineResult {
        let input = text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return PipelineResult(text: "") }

        // 1. Snippets become opaque placeholders, so neither style rules nor dictionary
        //    corrections can touch a URL or a signature the user typed exactly.
        let expanded = SnippetExpander.substitute(in: input, snippets: snippets)
        if let only = expanded.soleExpansion {
            return PipelineResult(text: only, snippets: expanded.fired)
        }

        // 2. Style.
        let styled = StyleRules.apply(style, to: expanded.text, vocabulary: vocabulary)

        // 3. Dictionary corrections last, so they win over everything before them.
        let (corrected, applied) = corrector.apply(to: styled)
        return PipelineResult(
            text: expanded.restore(in: corrected), corrections: applied, snippets: expanded.fired)
    }
}

// MARK: - Snippets

/// Swaps snippet triggers for placeholders, and back.
struct SnippetExpander {
    var text: String
    var expansions: [String] = []
    var fired: [String] = []

    /// Placeholders are private-use scalars: never produced by an engine or a model, caseless,
    /// and not letters — so word-fenced patterns treat them as a boundary.
    private static let placeholderBase: UInt32 = 0xE100
    private static let placeholderLimit = 0xFF

    static func isPlaceholder(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 else { return false }
        return scalar.value >= placeholderBase && scalar.value <= placeholderBase + UInt32(placeholderLimit)
    }

    private static func placeholder(_ index: Int) -> String {
        String(Character(UnicodeScalar(placeholderBase + UInt32(index))!))
    }

    /// The utterance was nothing but one trigger: the result is exactly the expansion.
    var soleExpansion: String? {
        guard expansions.count == 1 else { return nil }
        let rest = text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
        }
        return String(String.UnicodeScalarView(rest)) == Self.placeholder(0) ? expansions[0] : nil
    }

    func restore(in text: String) -> String {
        guard !expansions.isEmpty else { return text }
        var output = ""
        for char in text {
            if Self.isPlaceholder(char), let value = char.unicodeScalars.first?.value {
                let index = Int(value - Self.placeholderBase)
                output += index < expansions.count ? expansions[index] : ""
            } else {
                output.append(char)
            }
        }
        return output
    }

    static func triggerWords(_ trigger: String) -> [String] {
        trigger.precomposedStringWithCanonicalMapping
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    static func substitute(in text: String, snippets: [Snippet]) -> SnippetExpander {
        var result = SnippetExpander(text: text)
        // Longest trigger first, so "my work email" isn't pre-empted by "my email".
        let candidates = snippets
            .filter { $0.isEnabled && !$0.expansion.isEmpty }
            .map { (snippet: $0, words: triggerWords($0.trigger)) }
            .filter { !$0.words.isEmpty }
            .sorted { $0.words.joined(separator: " ").count > $1.words.joined(separator: " ").count }

        for (snippet, words) in candidates where result.expansions.count <= placeholderLimit {
            // Punctuation-tolerant: the engine may write "my Calendly-link," or "My calendly. Link".
            let body = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "[\\t \\p{P}]*")
            guard
                let regex = try? NSRegularExpression(
                    pattern: "(?<![\\p{L}\\p{N}])" + body + "(?![\\p{L}\\p{N}])", options: [.caseInsensitive])
            else { continue }

            let ns = NSString(string: result.text)
            let matches = regex.matches(in: result.text, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }

            let marker = placeholder(result.expansions.count)
            let dropsFullStop = endsWithLinkOrEmail(snippet.expansion)
            var output = ""
            var cursor = 0
            for match in matches {
                output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                output += marker
                cursor = match.range.location + match.range.length
                // The engine ends the utterance with a full stop; after a URL it would break the link.
                if dropsFullStop, cursor < ns.length, ns.substring(with: NSRange(location: cursor, length: 1)) == "." {
                    let rest = ns.substring(from: cursor + 1)
                    if rest.trimmingCharacters(in: .whitespaces).isEmpty || rest.hasPrefix("\n") { cursor += 1 }
                }
            }
            output += ns.substring(from: cursor)
            result.text = output
            result.expansions.append(snippet.expansion)
            result.fired.append(snippet.trigger)
        }
        return result
    }

    static func endsWithLinkOrEmail(_ text: String) -> Bool {
        guard let last = text.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) else { return false }
        return Token.isLinkLike(last.trimmingCharacters(in: CharacterSet(charactersIn: ")]>\"'”’")))
    }
}

// MARK: - Token classification

enum Token {
    private static let domainLike = makeRegex(
        "^[\\p{L}\\p{N}-]+(?:\\.[\\p{L}\\p{N}-]+)*\\.[A-Za-z]{2,}(?:[/?#]\\S*)?$")

    /// URLs, emails, bare domains and @handles — text whose exact form matters.
    static func isLinkLike(_ token: String) -> Bool {
        let lowered = token.lowercased()
        if lowered.contains("://") || lowered.hasPrefix("www.") || token.contains("@") { return true }
        return domainLike.matches(token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?")))
    }

    /// Very casual style lowercases a token unless its casing carries meaning.
    static func keepsCase(_ token: String) -> Bool {
        if isLinkLike(token) { return true }
        let core = token.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        if core.contains(where: \.isNumber) { return true }
        let letters = core.filter(\.isLetter)
        let uppers = letters.filter(\.isUppercase).count
        if letters.count >= 2 {
            if uppers == letters.count { return true }  // NASA, API
            if letters.last == "s", uppers >= 2, uppers == letters.count - 1 { return true }  // APIs
        }
        // Interior capitals are deliberate brand spellings: iPhone, macOS, GitHub.
        var sawLowercase = false
        for char in core {
            if char.isLowercase { sawLowercase = true } else if char.isUppercase, sawLowercase { return true }
        }
        return false
    }
}

// MARK: - Writing styles

enum StyleRules {
    private static let openers: Set<Character> = ["\"", "“", "‘", "'", "(", "["]
    private static let closers: Set<Character> = ["\"", "”", "’", "'", ")", "]"]
    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    /// "e.g." and "a.m." end in a full stop without ending the sentence.
    private static let dottedAbbreviation = makeRegex("^(?:\\p{L}\\.)+\\p{L}?\\.?$")
    private static let abbreviations: Set<String> = ["etc", "vs", "approx", "cf", "incl", "eg", "ie"]
    private static let listItem = makeRegex("^\\s*(?:\\d{1,3}[.)]|[-•*–])\\s")
    private static let innerSentenceBreak = makeRegex("[.!?…]+[\"”’)]*\\s+\\S")

    static func apply(_ style: WritingStyle, to text: String, vocabulary: [String]) -> String {
        switch style {
        case .formal: ensureTerminalPunctuation(capitalizeSentences(text))
        case .casual: dropFinalPeriodIfShort(capitalizeSentences(text))
        case .veryCasual: dropFinalPeriod(lowercase(text, vocabulary: vocabulary))
        case .excited: exclaim(capitalizeSentences(text))
        }
    }

    // MARK: Capitalisation

    /// Capitalises the first word of the text, of each line and of each sentence — unless the
    /// word carries its own casing ("iPhone"), or the full stop belonged to "e.g." or "…".
    static func capitalizeSentences(_ text: String) -> String {
        var chars = Array(text)
        var atStart = true
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\n" {
                atStart = true
                index += 1
                continue
            }
            if atStart {
                if char.isLetter {
                    var end = index
                    while end < chars.count, chars[end].isLetter || chars[end] == "'" || chars[end] == "’" { end += 1 }
                    let word = String(chars[index..<end])
                    if word == word.lowercased() {
                        let upper = Array(String(char).uppercased())
                        chars.replaceSubrange(index...index, with: upper)
                        end += upper.count - 1
                    }
                    atStart = false
                    index = end
                    continue
                }
                if char.isWhitespace || openers.contains(char) {
                    index += 1
                    continue
                }
                atStart = false  // a digit, a snippet, an emoji: the sentence has started
            }
            if terminators.contains(char) {
                var end = index + 1
                while end < chars.count, terminators.contains(chars[end]) || closers.contains(chars[end]) { end += 1 }
                let run = String(chars[index..<end])
                let isEllipsis = run.contains("…") || run.contains("..")
                if end < chars.count, chars[end].isWhitespace, !isEllipsis,
                    !(char == "." && endsAbbreviation(chars, at: index))
                {
                    atStart = true
                }
                index = end
                continue
            }
            index += 1
        }
        return String(chars)
    }

    private static func endsAbbreviation(_ chars: [Character], at dot: Int) -> Bool {
        var start = dot
        while start > 0, chars[start - 1].isLetter || chars[start - 1] == "." { start -= 1 }
        let token = String(chars[start...dot])
        if dottedAbbreviation.matches(token), token.filter({ $0 == "." }).count >= 2 { return true }
        return abbreviations.contains(token.lowercased().filter(\.isLetter))
    }

    // MARK: End of text

    private static func lastIndex(of text: String) -> String.Index? {
        text.lastIndex { !$0.isWhitespace }
    }

    private static func lastLineIsListItem(_ text: String) -> Bool {
        let lastLine = text.split(separator: "\n", omittingEmptySubsequences: true).last.map(String.init) ?? text
        return listItem.matches(lastLine)
    }

    private static func endsWithAbbreviation(_ text: String) -> Bool {
        let chars = Array(text)
        guard let dot = chars.lastIndex(of: "."), dot == chars.count - 1 else { return false }
        return endsAbbreviation(chars, at: dot)
    }

    /// Formal: the text ends with a full stop, unless it already ends a sentence, ends in a
    /// snippet, an emoji or a list item.
    static func ensureTerminalPunctuation(_ text: String) -> String {
        guard let last = lastIndex(of: text) else { return text }
        let char = text[last]
        if terminators.contains(char) || SnippetExpander.isPlaceholder(char) { return text }
        if char == "," || char == ";" {
            return text.replacingCharacters(in: last...last, with: ".")
        }
        if closers.contains(char) {
            // `He said "hi."` is finished; `He said "hi"` isn't.
            let inner = text[..<last].last { !closers.contains($0) }
            if let inner, terminators.contains(inner) || SnippetExpander.isPlaceholder(inner) { return text }
            return text + "."
        }
        guard char.isLetter || char.isNumber, !lastLineIsListItem(text) else { return text }
        return String(text[...last]) + "."
    }

    /// Casual: one short sentence reads like a chat message without its final period.
    static func dropFinalPeriodIfShort(_ text: String) -> String {
        guard !text.contains("\n"), !innerSentenceBreak.matches(text) else { return text }
        let words = text.split { $0.isWhitespace }.count
        guard words <= TextPipeline.casualPeriodWordLimit else { return text }
        return dropFinalPeriod(text)
    }

    /// Removes one final full stop — never an ellipsis, and never the dot of "a.m.".
    static func dropFinalPeriod(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix(".."), !endsWithAbbreviation(text) else { return text }
        return String(text.dropLast())
    }

    /// Excited: the final full stop becomes one exclamation mark. Questions stay questions.
    static func exclaim(_ text: String) -> String {
        guard let last = lastIndex(of: text) else { return text }
        let char = text[last]
        switch char {
        case "?", "!", "…": return text
        case ".":
            guard !text.hasSuffix(".."), !endsWithAbbreviation(text) else { return text }
            return text.replacingCharacters(in: last...last, with: "!")
        case ",", ";":
            return text.replacingCharacters(in: last...last, with: "!")
        default:
            guard char.isLetter || char.isNumber, !lastLineIsListItem(text) else { return text }
            return String(text[...last]) + "!"
        }
    }

    // MARK: Very casual

    private static let nonSpace = makeRegex("\\S+")

    /// Lowercases everything except acronyms, tokens with digits, links, emails, handles,
    /// brand casing — and dictionary terms, which are restored to their exact spelling.
    static func lowercase(_ text: String, vocabulary: [String]) -> String {
        var output = nonSpace.replacingMatches(in: text) { match, ns in
            let token = ns.substring(with: match.range)
            return Token.keepsCase(token) ? nil : token.lowercased()
        }
        let terms = vocabulary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != $0.lowercased() }
            .sorted { $0.count > $1.count }
        for term in terms {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            output = regex.replacingMatches(in: output, template: NSRegularExpression.escapedTemplate(for: term))
        }
        return output
    }
}
