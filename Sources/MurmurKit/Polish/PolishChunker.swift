import Foundation

/// One part of a long dictation, polished on its own (`PolishService.polishLong`).
public struct PolishChunk: Sendable, Equatable {
    /// The part, without the whitespace around it.
    public let text: String
    /// The whitespace before it in the whole text: "" for the first part, otherwise " ",
    /// "\n" or "\n\n". `PolishChunker.join` puts it back.
    public let separatorBefore: String
    /// The end of the part before, as dictated: whole sentences, at most
    /// `PolishChunker.contextWords` words. `nil` for the first part.
    public let context: String?
    /// Not the last part: the text goes on after it.
    public let continues: Bool

    public init(text: String, separatorBefore: String, context: String?, continues: Bool) {
        self.text = text
        self.separatorBefore = separatorBefore
        self.context = context
        self.continues = continues
    }
}

/// Splits a long prepared text into parts that can be polished at the same time, and joins
/// the polished parts back up.
///
/// Parts end only at the end of a sentence or a line, never where the next sentence corrects
/// or continues this one ("…Thursday. No wait, Friday.", "First… Second…"), and each carries
/// the end of the part before it as context. The split is greedy from the start, so the
/// parts a growing text has finished (`closedOnly`) are the parts the whole text will have:
/// a part polished while the person is still talking is the same request at key-up.
public enum PolishChunker {
    /// Shorter texts are polished in one piece, as before.
    public static let minimumWords = 250
    /// A part closes at the first sentence end from here on…
    public static let targetWords = 150
    /// …or at a paragraph break from here on…
    public static let minWords = 90
    /// …but not before a sentence that starts "and", "but", "so"… until this long…
    public static let maxWords = 260
    /// …or before a correction or the next list item until this long.
    public static let hardMaxWords = 400
    /// At most this much of the part before goes along as context.
    public static let contextWords = 60

    /// The parts of `text`, which is a prepared transcript (`TextPipeline.prepare`, so
    /// trimmed): one part, `text` itself, when it's under `minimumWords` words or has no
    /// place to split.
    ///
    /// - Parameter closedOnly: only the parts already finished: those followed by the start
    ///   of a part whose first word is known. Nothing while the text is under `minimumWords`
    ///   words, since it may yet be polished in one piece.
    public static func chunks(_ text: String, closedOnly: Bool = false) -> [PolishChunk] {
        let scan = Scan(text)
        guard scan.tokens.count >= minimumWords else {
            return closedOnly ? [] : [whole(text)]
        }
        var parts = split(scan)
        if closedOnly {
            parts.removeLast()
            // A part is decided by the first word after it; the text's last word may still grow.
            if let last = parts.last, scan.segments[last.upperBound].lowerBound == scan.tokens.count - 1 {
                parts.removeLast()
            }
        } else if parts.count == 1 {
            return [whole(text)]
        }
        return parts.indices.map { index in
            let tokens = scan.tokenRange(of: parts[index])
            return PolishChunk(
                text: scan.text(tokens),
                separatorBefore: tokens.lowerBound == 0 ? "" : String(scan.runs[tokens.lowerBound - 1]),
                context: index == 0 ? nil : context(after: parts[index - 1], in: scan),
                continues: closedOnly || index < parts.count - 1
            )
        }
    }

    /// The polished parts, in order, joined with the whitespace that separated them.
    ///
    /// A part that isn't the last keeps the sentence end it was dictated with: a model told
    /// the text goes on can still drop the full stop, or, in the excited style, end the part
    /// with the "!" meant for the end of the message. `TextPipeline.finalize` styles the
    /// real ending once, on the joined text.
    public static func join(_ outputs: [String], chunks: [PolishChunk], style: WritingStyle) -> String {
        var text = ""
        for (output, chunk) in zip(outputs, chunks) {
            var part = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if chunk.continues { part = restoreBoundary(part, input: chunk.text, style: style) }
            text += chunk.separatorBefore + part
        }
        return text
    }

    /// How many parts may be polished at once. Cloud APIs take several; Claude Code starts a
    /// process per part; a local server and Apple's on-device model take one at a time.
    public static func concurrency(for provider: PolishProvider, localEndpoint: Bool) -> Int {
        switch provider {
        case .anthropic: 4
        case .openAICompatible: localEndpoint ? 1 : 3
        case .claudeCode: 3
        case .appleIntelligence, .off: 1
        }
    }

    // MARK: Splitting

    private static func whole(_ text: String) -> PolishChunk {
        PolishChunk(text: text, separatorBefore: "", context: nil, continues: false)
    }

    /// What the sentence after a boundary says about splitting before it.
    enum Cue: Equatable {
        case none
        /// It continues the one before ("And…", "So…"): no split until `maxWords`.
        case weak
        /// It corrects the one before or goes on with a list ("No wait…", "Second…", "2."):
        /// no split until `hardMaxWords`.
        case strong
    }

    static let strongCues: Set<String> = [
        "no", "wait", "scratch", "actually", "sorry", "instead", "rather",
        "first", "firstly", "second", "secondly", "third", "thirdly", "fourth", "fourthly", "fifth", "fifthly",
        "next", "finally", "lastly",
    ]
    static let weakCues: Set<String> = ["and", "but", "or", "so", "then", "also"]

    /// Greedy, left to right: each part closes at the first sentence end that qualifies, so
    /// a part depends only on the text up to the first word after it.
    private static func split(_ scan: Scan) -> [Range<Int>] {
        var parts: [Range<Int>] = []
        var start = 0
        var words = 0
        for index in scan.segments.indices {
            words += scan.segments[index].count
            guard index < scan.segments.count - 1 else { break }
            let separator = scan.runs[scan.segments[index].upperBound - 1]
            let next = scan.tokens[scan.segments[index + 1].lowerBound]
            if closes(words: words, paragraph: separator.filter(\.isNewline).count >= 2, cue: cue(next)) {
                parts.append(start..<(index + 1))
                start = index + 1
                words = 0
            }
        }
        parts.append(start..<scan.segments.count)
        return parts
    }

    private static func closes(words: Int, paragraph: Bool, cue: Cue) -> Bool {
        guard words >= minWords else { return false }
        switch cue {
        case .strong where words < hardMaxWords: return false
        case .weak where words < maxWords: return false
        default: break
        }
        return paragraph || words >= targetWords
    }

    static func cue(_ token: Substring) -> Cue {
        if isListMarker(token) { return .strong }
        let word = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if strongCues.contains(word) || isOrdinalNumber(word) { return .strong }
        return weakCues.contains(word) ? .weak : .none
    }

    /// "2nd", "3rd", "21st".
    private static func isOrdinalNumber(_ word: String) -> Bool {
        for suffix in ["st", "nd", "rd", "th"] where word.hasSuffix(suffix) {
            let number = word.dropLast(suffix.count)
            return !number.isEmpty && number.allSatisfy(\.isNumber)
        }
        return false
    }

    /// "2.", "3)", "-", "•": the start of a dictated list item.
    private static func isListMarker(_ token: Substring) -> Bool {
        if token.count == 1, let only = token.first, bullets.contains(only) { return true }
        guard let mark = token.last, mark == "." || mark == ")" else { return false }
        let number = token.dropLast()
        return (1...3).contains(number.count) && number.allSatisfy(\.isNumber)
    }

    /// Whole sentences from the end of `part`, up to `contextWords` words; the last words of
    /// its final sentence when that alone is longer.
    private static func context(after part: Range<Int>, in scan: Scan) -> String {
        var first = part.upperBound
        var words = 0
        while first > part.lowerBound, words + scan.segments[first - 1].count <= contextWords {
            first -= 1
            words += scan.segments[first].count
        }
        let end = scan.segments[part.upperBound - 1].upperBound
        guard first < part.upperBound else { return scan.text((end - contextWords)..<end) }
        return scan.text(scan.segments[first].lowerBound..<end)
    }

    // MARK: Sentence ends

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "”", "’", "'", ")", "]", "}", "»"]
    private static let openers: Set<Character> = ["\"", "“", "‘", "'", "(", "[", "{", "«"]
    private static let bullets: Set<Character> = ["-", "–", "—", "•", "*"]
    /// Lowercased, without the final period. Single capitals ("J.", "U.S.") are caught apart.
    static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "mt", "vs", "e.g", "i.e", "cf", "al",
        "approx", "dept", "est", "fig", "inc", "ltd", "co", "corp", "gen", "gov", "lt", "col",
        "capt", "sgt", "rev", "fr", "ave", "blvd", "rd", "vol", "pp",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
    ]

    /// Whether `token` ends a sentence: `[.!?…]`, then any closing quotes or brackets.
    /// "Dr." and "e.g." don't, nor does a list number opening a line ("2. Then…").
    static func endsSentence(_ token: Substring, startsSegment: Bool) -> Bool {
        var core = token
        while let last = core.last, closers.contains(last) { core = core.dropLast() }
        guard let mark = core.last, terminators.contains(mark) else { return false }
        if startsSegment, isListMarker(token) { return false }
        guard mark == "." else { return true }
        let stem = core.dropLast().drop { openers.contains($0) }
        // "and then..." is an ellipsis.
        if stem.last == "." { return true }
        if let initial = stem.split(separator: ".").last, initial.count == 1, initial.first?.isUppercase == true {
            return false
        }
        return !abbreviations.contains(stem.lowercased())
    }

    /// Whether `token` can open a sentence: a capital or a digit after any opening quote, or
    /// a list bullet. Prepared text keeps the engine's capitals; style casing comes later.
    static func startsSentence(_ token: Substring) -> Bool {
        guard let first = token.first(where: { !openers.contains($0) }) else { return false }
        return first.isUppercase || first.isNumber || bullets.contains(first)
    }

    /// Puts back the sentence end the input part had, when the output lost or changed it.
    static func restoreBoundary(_ output: String, input: String, style: WritingStyle) -> String {
        guard let wanted = finalMark(of: input), !output.isEmpty else { return output }
        var characters = Array(output)
        var index = characters.count - 1
        while index > 0, closers.contains(characters[index]) { index -= 1 }
        let last = characters[index]
        if terminators.contains(last) {
            // The style's "!" belongs to the end of the whole message, not of each part.
            if style == .excited, last == "!", wanted == "." { characters[index] = "." }
        } else if last == "," || last == ";" || last == ":" {
            characters[index] = wanted
        } else {
            characters.append(wanted)
        }
        return String(characters)
    }

    /// The `[.!?…]` a text ends with, before any closing quotes or brackets.
    private static func finalMark(of text: String) -> Character? {
        var core = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        while let last = core.last, closers.contains(last) { core = core.dropLast() }
        return core.last.flatMap { terminators.contains($0) ? $0 : nil }
    }
}

// MARK: - Scan

/// A text as words and the whitespace between them, grouped into sentences.
private struct Scan {
    /// Runs of non-whitespace.
    var tokens: [Substring] = []
    /// `runs[i]` is the whitespace between `tokens[i]` and `tokens[i + 1]`.
    var runs: [Substring] = []
    /// Sentences (and lines) as ranges of `tokens`, in order, covering every token.
    var segments: [Range<Int>] = []

    init(_ text: String) {
        var index = text.startIndex
        while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
        while index < text.endIndex {
            let tokenStart = index
            while index < text.endIndex, !text[index].isWhitespace { index = text.index(after: index) }
            tokens.append(text[tokenStart..<index])
            let runStart = index
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            if index < text.endIndex { runs.append(text[runStart..<index]) }
        }
        guard !tokens.isEmpty else { return }

        var segmentStart = 0
        for (index, run) in runs.enumerated() {
            let ends = run.contains(where: \.isNewline)
                || (PolishChunker.endsSentence(tokens[index], startsSegment: index == segmentStart)
                    && PolishChunker.startsSentence(tokens[index + 1]))
            if ends {
                segments.append(segmentStart..<(index + 1))
                segmentStart = index + 1
            }
        }
        segments.append(segmentStart..<tokens.count)
    }

    /// The tokens a run of whole segments covers.
    func tokenRange(of segmentRange: Range<Int>) -> Range<Int> {
        segments[segmentRange.lowerBound].lowerBound..<segments[segmentRange.upperBound - 1].upperBound
    }

    /// The original text of a run of tokens, whitespace included.
    func text(_ range: Range<Int>) -> String {
        var text = String(tokens[range.lowerBound])
        for index in (range.lowerBound + 1)..<range.upperBound {
            text += runs[index - 1]
            text += tokens[index]
        }
        return text
    }
}
