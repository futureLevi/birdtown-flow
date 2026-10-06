import Foundation

// The deterministic half of `TextPipeline.prepare`: fillers, stutters, spoken commands and
// whitespace. Parakeet already punctuates and capitalises, so every rule here is a narrow
// repair of something speech produces, never a rewrite of what the engine decided.

/// Marks "capitalise the next word" after a removal exposes a sentence start. A private-use
/// scalar can't occur in engine output, and it's resolved before `prepare` returns.
let capitalizeMark: Character = "\u{E000}"

enum Cleanup {
    // MARK: Fillers

    /// One filler token. Elongations ("ummm", "hmmm") are the same sound, so they're folded in;
    /// "err" is deliberately absent because it's a real word.
    private static let fillerCore = "(u+m+|u+h+m*|e+r+m+|e+r|a+h+|h+m+|m{2,})"
    private static let filler = wordFenceBefore + fillerCore + wordFenceAfter
    /// Text start, a line start, or just after a sentence ended.
    private static let sentenceStart = "(^|[.!?…][\"”’)]?[ \\t]+|\\n[ \\t]*)"

    /// "Um, so I think" → "So I think". Consumes a run of fillers and their punctuation.
    private static let leadingFillers = makeRegex(
        sentenceStart + "(?:" + filler + "(?:[ \\t]*(?:\\.\\.\\.|…|[,.!?;:]))?[ \\t]*)+", caseInsensitive: true)

    /// "So, um, I was" → "So, I was": a one-word introduction keeps its comma.
    private static let introThenFiller = makeRegex(
        sentenceStart + "(\u{E000}?\\p{L}+),(?:[ \\t]*" + filler + "[ \\t]*,?)+[ \\t]*", caseInsensitive: true)

    /// Everything else: the filler goes, with a comma on either side of it. "the, uh, store"
    /// reads "the store" — the pause commas belonged to the filler, not the sentence.
    private static let innerFiller = makeRegex(",?[ \\t]*" + filler + "(?:[ \\t]*,)?", caseInsensitive: true)

    /// "ER", "UM" in capitals are acronyms (the emergency room, a university), not hesitation.
    private static func isAcronym(_ token: String) -> Bool {
        token.count >= 2 && token == token.uppercased() && token != token.lowercased()
    }

    static func removeFillers(_ text: String) -> String {
        var text = leadingFillers.replacingMatches(in: text) { match, ns in
            let removed = ns.substring(with: match.range)
            let tokens = removed.split { !$0.isLetter }.map(String.init)
            if tokens.contains(where: isAcronym) { return nil }
            return (match.group(1, in: ns) ?? "") + String(capitalizeMark)
        }
        text = introThenFiller.replacingMatches(in: text) { match, ns in
            let removed = ns.substring(with: match.range)
            if removed.split(whereSeparator: { !$0.isLetter }).dropFirst().map(String.init).contains(where: isAcronym) {
                return nil
            }
            return (match.group(1, in: ns) ?? "") + (match.group(2, in: ns) ?? "") + ", "
        }
        text = innerFiller.replacingMatches(in: text) { match, ns in
            guard let token = match.group(1, in: ns), !isAcronym(token) else { return nil }
            // "a 5 mm screw": after a number, "mm" is millimetres.
            if token.lowercased().hasPrefix("m") {
                let before = ns.substring(to: match.range.location).trimmingCharacters(in: .whitespaces)
                if before.last?.isNumber == true { return nil }
            }
            return ""
        }
        return text
    }

    // MARK: Stutters

    /// Words whose immediate repetition is never intended. "that that" and "had had" are
    /// grammatical, so they're absent; so are "you" ("tell you you were right"), "it"
    /// ("when I found it it was broken"), "her" ("gave her her keys"), "is", "do", "so",
    /// "in" and "on" ("turn it on on Monday").
    static let stutterWords = [
        "i", "me", "my", "we", "us", "our", "your", "he", "him", "his", "she", "they", "them",
        "their", "the", "a", "an", "to", "of", "for", "with", "and", "or", "but", "if", "at",
        "by", "from", "this", "i'm", "it's", "we're", "you're", "they're", "i've", "i'll", "i'd",
        "we'll", "we've",
    ]

    /// Of those, the ones the engine often splits with a comma ("I, I think").
    static let commaStutterWords = ["i", "the", "a", "an", "to", "of", "and", "but", "or", "with", "we", "they"]

    private static func alternation(_ words: [String]) -> String {
        words.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: "'", with: "['’]") }
            .joined(separator: "|")
    }

    private static let stutter = makeRegex(
        wordFenceBefore + "(" + alternation(stutterWords) + ")(?:[ \\t]+\\1)+" + wordFenceAfter, caseInsensitive: true)
    private static let commaStutter = makeRegex(
        wordFenceBefore + "(" + alternation(commaStutterWords) + ")(?:,?[ \\t]+\\1)+" + wordFenceAfter,
        caseInsensitive: true)
    /// "w- what", "to- tomorrow": a cut-off fragment, a dash, then the word it was starting.
    private static let restart = makeRegex(
        "(?<![\\p{L}\\p{N}'’\\-])(\\p{L}{1,8})[-–—][ \\t]+(\\p{L}[\\p{L}'’]*)", caseInsensitive: true)

    static func collapseStutters(_ text: String) -> String {
        var text = commaStutter.replacingMatches(in: text, template: "$1")
        text = stutter.replacingMatches(in: text, template: "$1")
        text = restart.replacingMatches(in: text) { match, ns in
            guard let fragment = match.group(1, in: ns), let word = match.group(2, in: ns),
                word.lowercased().hasPrefix(fragment.lowercased())
            else { return nil }  // "pre- and post-war" is a real construction
            // Keep the capital the fragment carried at a sentence start.
            guard fragment.first?.isUppercase == true, let first = word.first else { return word }
            return first.uppercased() + word.dropFirst()
        }
        return text
    }

    // MARK: Spoken commands

    /// "new line"/"new paragraph", swallowing the comma the engine put before it and whatever
    /// punctuation it put after. A full stop before it stays — it ended the previous sentence.
    private static let command = makeRegex(
        "(?:[ \\t]*[,;])?[ \\t]*" + wordFenceBefore + "new[ \\t\\-]+(paragraph|line)" + wordFenceAfter
            + "[ \\t]*[.,;:!?]*[ \\t]*",
        caseInsensitive: true)
    private static let followedByOf = makeRegex("^of(?![\\p{L}\\p{N}])", caseInsensitive: true)
    /// "a new line of products", "the new paragraph" — a noun phrase, not a command.
    private static let determiners: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those", "my", "your", "our", "their", "his", "her",
        "its", "any", "another", "every", "each", "no", "one", "whole", "entire", "brand", "first", "next",
    ]

    static func applySpokenCommands(_ text: String) -> String {
        command.replacingMatches(in: text) { match, ns in
            let before = ns.substring(to: match.range.location)
            let previousWord = before.split { !$0.isLetter && $0 != "'" && $0 != "’" }.last.map { $0.lowercased() }
            if let previousWord, determiners.contains(previousWord), !before.hasSuffix(".") { return nil }
            let after = ns.substring(from: match.range.location + match.range.length)
            if followedByOf.matches(after) { return nil }
            let isParagraph = match.group(1, in: ns)?.lowercased() == "paragraph"
            return (isParagraph ? "\n\n" : "\n") + String(capitalizeMark)
        }
    }

    // MARK: Whitespace and punctuation

    private static let horizontalSpace = makeRegex("[ \\t\\u00A0]+")
    private static let spaceAroundNewline = makeRegex("[ \\t]*\\n[ \\t]*")
    private static let spaceBeforePunctuation = makeRegex("[ \\t]+([,.!?:;])")
    private static let repeatedCommas = makeRegex(",(?:[ \\t]*,)+")
    private static let commaBeforeStop = makeRegex(",[ \\t]*([.!?;:])")
    /// ". ," → "." — but "e.g.," is correct punctuation, so a bare full stop needs the space.
    private static let commaAfterStop = makeRegex("(?:([!?;:])[ \\t]*|(\\.)[ \\t]+),+")
    private static let leadingCommas = makeRegex("(^|\\n)(\u{E000}?)[ \\t]*[,;]+[ \\t]*")
    private static let extraBlankLines = makeRegex("\\n{3,}")

    static func tidy(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        text = horizontalSpace.replacingMatches(in: text, template: " ")
        text = spaceAroundNewline.replacingMatches(in: text, template: "\n")
        text = spaceBeforePunctuation.replacingMatches(in: text, template: "$1")
        text = repeatedCommas.replacingMatches(in: text, template: ",")
        text = commaBeforeStop.replacingMatches(in: text, template: "$1")
        text = commaAfterStop.replacingMatches(in: text, template: "$1$2")
        text = leadingCommas.replacingMatches(in: text, template: "$1$2")
        text = extraBlankLines.replacingMatches(in: text, template: "\n\n")
        text = resolveCapitalizeMarks(text)
        // Trailing breaks are trimmed too: a stray "\n" typed into Slack would send the message.
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Capitalises the first word after each mark — unless it carries its own casing
    /// ("iPhone"), which a sentence start doesn't override.
    static func resolveCapitalizeMarks(_ text: String) -> String {
        guard text.contains(capitalizeMark) else { return text }
        let chars = Array(text)
        var output = ""
        var pending = false
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == capitalizeMark {
                pending = true
                index += 1
                continue
            }
            if pending, char.isLetter {
                var end = index
                while end < chars.count, chars[end].isLetter || chars[end] == "'" || chars[end] == "’" { end += 1 }
                let word = String(chars[index..<end])
                output += word == word.lowercased() ? word.prefix(1).uppercased() + word.dropFirst() : word
                pending = false
                index = end
                continue
            }
            if pending, !(char.isWhitespace || "\"“‘'(".contains(char)) { pending = false }
            output.append(char)
            index += 1
        }
        return output
    }
}
