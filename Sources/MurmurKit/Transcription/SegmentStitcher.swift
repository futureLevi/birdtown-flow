import Foundation

/// Turns the windows of a long recording back into one transcript.
///
/// Windows overlap: each decodes some audio on either side of the stretch it keeps. A word
/// belongs to the window whose kept stretch holds the start of its first token, so every
/// word is written once, by the window that heard it with context on both sides. Casing and
/// punctuation are the model's; nothing here rewrites them.
///
/// Tokens are FluidAudio's timing tokens, where a word-start piece's `▁` has already become
/// a leading space.
public enum SegmentStitcher {
    /// One decoded token, on the recording's clock.
    public struct TimedToken: Sendable, Equatable {
        public let text: String
        /// Seconds from the start of the recording.
        public let start: Double
        /// Its position in the window's own token list.
        public let index: Int

        public init(text: String, start: Double, index: Int) {
            self.text = text
            self.start = start
            self.index = index
        }
    }

    /// A word: a word-start piece and every piece up to the next one (the rest of the word,
    /// and punctuation after it).
    public struct TimedWord: Sendable, Equatable {
        /// Lowercased, without boundary punctuation; interior apostrophes and hyphens stay,
        /// so "we'll" never equals "well".
        public let core: String
        /// When its first token starts, in seconds from the start of the recording.
        public let start: Double
        /// Positions in the token list it was grouped from.
        public let tokens: Range<Int>

        public init(core: String, start: Double, tokens: Range<Int>) {
            self.core = core
            self.start = start
            self.tokens = tokens
        }
    }

    /// What one window contributes.
    public struct Kept: Sendable, Equatable {
        /// The kept words' tokens, in order.
        public var tokens: [TimedToken]
        /// Punctuation the window heard after a word the previous window kept (its "." when
        /// the previous window ended before hearing it). `join` attaches it only where the
        /// previous text has no punctuation of its own, less any marks it already ends with.
        public var leadingPunctuation: String
        /// The last kept words, at most `seamRun`, for the next window's seam check. Empty
        /// when nothing was kept.
        public var lastWords: [TimedWord]
        /// The first word heard after the kept stretch, which this window leaves to the next
        /// one, for that window's seam check. `nil` for the tail, or when none was heard.
        public var nextWord: TimedWord?
        /// `tokens` as text, trimmed.
        public var text: String

        /// The last kept word. `nil` when nothing was kept.
        public var lastWord: TimedWord? { lastWords.last }

        public init(
            tokens: [TimedToken] = [], leadingPunctuation: String = "", lastWords: [TimedWord] = [],
            nextWord: TimedWord? = nil, text: String = ""
        ) {
            self.tokens = tokens
            self.leadingPunctuation = leadingPunctuation
            self.lastWords = lastWords
            self.nextWord = nextWord
            self.text = text
        }
    }

    /// One window's text for `join`: its kept text (boosted or not) and its leading punctuation.
    public struct Part: Sendable, Equatable {
        public var leadingPunctuation: String
        public var text: String

        public init(leadingPunctuation: String = "", text: String) {
            self.leadingPunctuation = leadingPunctuation
            self.text = text
        }
    }

    /// A word both windows wrote at a seam starts within this much of itself in each.
    public static let seamTolerance = 0.16

    /// How far apart two windows may time the same run of two or more words at a seam. Near
    /// the end of a window's audio the model's timings drift: CI's long recording had "and
    /// tell" timed before a cut by one window and after it by the next. A run of matching
    /// words is unlikely by chance, so it may drift this far; FluidAudio's own chunk merge
    /// allows the same (half its 2 s overlap). A single word stays within `seamTolerance`.
    public static let runTolerance = 1.0

    /// How many of the previous window's last words are looked for at a seam.
    public static let seamRun = 4

    /// Punctuation that ends a part well enough that a following part's leading punctuation
    /// isn't needed.
    private static let closingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", "…"]

    // MARK: - Words

    /// Groups tokens into words. Tokens before the first word start (the end of a word the
    /// window's audio began in the middle of, or punctuation) belong to no word.
    ///
    /// A mirror of FluidAudio's `startsWordPiece`: a word starts at a boundary piece that
    /// isn't punctuation, or at a boundary apostrophe or hyphen followed by a continuation
    /// ("▁'" "cause"). Running each word to the next start includes everything FluidAudio's
    /// `wordExtent` would ("we" "'" "ll", "co" "-" "op") and the punctuation after it, so no
    /// token is ever left out.
    public static func words(_ tokens: [TimedToken]) -> [TimedWord] {
        let pieces = tokens.map(\.text)
        var words: [TimedWord] = []
        var index = pieces.indices.first { startsWord(pieces, at: $0) }
        while let first = index {
            var end = first + 1
            while end < pieces.count, !startsWord(pieces, at: end) { end += 1 }
            words.append(TimedWord(core: core(pieces[first..<end]), start: tokens[first].start, tokens: first..<end))
            index = end < pieces.count ? end : nil
        }
        return words
    }

    // MARK: - Keeping

    /// The words of one window that start inside `keep`, lined up with the previous window.
    ///
    /// Each window decodes about 2 s before its kept stretch, so it hears again the last
    /// words the previous window wrote. When it finds them (the same words, in order, timed
    /// close to where the previous window timed them), it keeps everything after its own copy
    /// of the last one, whichever side of the cut each window placed the words. That writes
    /// each word once even when the two windows time a few words near the cut differently.
    ///
    /// When it can't find them, each word belongs to the window holding the start of its
    /// first token, and the words either side of the cut are compared: same core, starting
    /// within `seamTolerance`.
    ///
    /// - Parameters:
    ///   - tokens: the window's tokens, in order, timed on the recording's clock.
    ///   - keep: the window's kept stretch, in seconds.
    ///   - tail: the last words the previous window kept (its `lastWords`), oldest first.
    ///   - following: the first word the previous window heard after the cut, and so left to
    ///     this one (its `nextWord`). Without the alignment, when this window hears that word
    ///     just before the cut, neither window would write it, so this one keeps it.
    public static func keep(
        _ tokens: [TimedToken], in keep: Range<Double>, after tail: [TimedWord], following: TimedWord? = nil
    ) -> Kept {
        let words = Self.words(tokens)
        let end = words.firstIndex { $0.start >= keep.upperBound } ?? words.count
        let kept: ArraySlice<TimedWord>
        let leadingFrom: Double
        if let anchor = align(tail, in: words[..<end]) {
            kept = words[(anchor + 1)..<end]
            // The previous window wrote up to this window's copy of its last word, so what
            // this window heard right after that word is the punctuation that closes it.
            leadingFrom = -Double.infinity
        } else {
            var start = words.firstIndex { keep.contains($0.start) } ?? end
            if let previous = tail.last, start < end, isSameWord(words[start], previous) {
                start += 1
            }
            if let following, start > 0, words[start - 1].start < keep.lowerBound,
               isSameWord(words[start - 1], following),
               !(tail.last.map { isSameWord(words[start - 1], $0) } ?? false) {
                start -= 1
            }
            kept = words[start..<max(start, end)]
            leadingFrom = keep.lowerBound
        }

        // Punctuation right before the first kept word that closes the word before it: the
        // previous window's last word, which that window may have stopped hearing before its
        // punctuation. Only the run straight after a word's last letter counts, so the
        // apostrophe in "don't" or the point in "3.5" is never taken for it.
        let firstKept = kept.first?.tokens.lowerBound ?? (end < words.count ? words[end].tokens.lowerBound : tokens.count)
        var leading = ""
        var index = firstKept - 1
        while index >= 0, isPunctuation(tokens[index].text) {
            if tokens[index].start >= leadingFrom, tokens[index].start < keep.upperBound {
                leading = tokens[index].text.trimmingCharacters(in: .whitespaces) + leading
            }
            index -= 1
        }

        let keptTokens = kept.flatMap { tokens[$0.tokens] }
        let text = keptTokens.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let lastWords = Array((tail + kept).suffix(seamRun))
        return Kept(
            tokens: keptTokens, leadingPunctuation: leading, lastWords: kept.isEmpty ? [] : lastWords,
            nextWord: end < words.count ? words[end] : nil, text: text
        )
    }

    /// `keep(_:in:after:following:)` with only the previous window's last word, if any.
    public static func keep(
        _ tokens: [TimedToken], in keep: Range<Double>, after previous: TimedWord?, following: TimedWord? = nil
    ) -> Kept {
        Self.keep(tokens, in: keep, after: previous.map { [$0] } ?? [], following: following)
    }

    /// Where this window heard the previous window's last words: the index of its copy of
    /// the last one, or `nil`. The longest run of `tail` found wins. A run of two or more
    /// matches within `runTolerance` per word; a single word only within `seamTolerance`,
    /// as a repeated short word ("the the") is too likely to match by chance. Among equal
    /// runs, the one timed closest to the previous window's wins.
    static func align(_ tail: [TimedWord], in words: ArraySlice<TimedWord>) -> Int? {
        guard let last = tail.last else { return nil }
        for length in stride(from: min(tail.count, seamRun), through: 1, by: -1) {
            let run = Array(tail.suffix(length))
            let tolerance = (length > 1 ? runTolerance : seamTolerance) + 1e-9
            var best: (index: Int, distance: Double)?
            for end in words.indices where end - (length - 1) >= words.startIndex {
                let candidate = words[(end - (length - 1))...end]
                guard zip(candidate, run).allSatisfy({
                    $0.core == $1.core && abs($0.start - $1.start) <= tolerance
                }) else { continue }
                let distance = abs(words[end].start - last.start)
                if distance < best?.distance ?? .infinity { best = (end, distance) }
            }
            if let best { return best.index }
        }
        return nil
    }

    /// The same word heard by two windows: same core, starting within `seamTolerance`.
    private static func isSameWord(_ a: TimedWord, _ b: TimedWord) -> Bool {
        a.core == b.core && abs(a.start - b.start) <= seamTolerance + 1e-9
    }

    // MARK: - Joining

    /// The windows' texts as one transcript: single spaces between parts, a part's leading
    /// punctuation attached only where the text before it has none, and never repeating a
    /// mark it already ends with. Capitalisation is never changed.
    public static func join(_ parts: [Part]) -> String {
        var joined = ""
        for part in parts {
            let leading = part.leadingPunctuation.trimmingCharacters(in: .whitespaces)
            if !leading.isEmpty, let last = joined.last, !closingPunctuation.contains(last) {
                joined += unwritten(leading, after: joined)
            }
            let text = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            joined += joined.isEmpty ? text : " " + text
        }
        return joined
    }

    /// `leading` without the marks `text` already ends with. When the windows line up, the
    /// run after the previous window's last word is taken wherever this window heard it, so
    /// a closing quote, bracket or apostrophe both heard is in both: `players'` then `'`
    /// adds nothing, `said "yes"` then `".` adds only the ".".
    private static func unwritten(_ leading: String, after text: String) -> String {
        // Longest first. A prefix longer than `text` simply isn't its suffix, so the whole
        // transcript so far is never counted.
        let overlap = stride(from: leading.count, through: 1, by: -1).first {
            text.hasSuffix(String(leading.prefix($0)))
        } ?? 0
        return String(leading.dropFirst(overlap))
    }

    /// Words written on both sides of a seam ("the the", or "and tell and tell", across two
    /// parts) that `reference` (the same recording transcribed whole) doesn't repeat. The
    /// longest run of up to `seamRun` words is reported for each seam. For the speech smoke
    /// test.
    public static func doubledSeams(_ parts: [String], reference: String) -> [String] {
        func cores(_ text: String) -> [String] {
            text.split(whereSeparator: \.isWhitespace).map { core(CollectionOfOne(String($0))) }.filter { !$0.isEmpty }
        }
        let texts = parts.map(cores).filter { !$0.isEmpty }
        let said = cores(reference)
        var doubled: [String] = []
        for (before, after) in zip(texts, texts.dropFirst()) {
            let longest = min(seamRun, before.count, after.count)
            guard let length = stride(from: longest, through: 1, by: -1).first(where: {
                Array(before.suffix($0)) == Array(after.prefix($0))
            }) else { continue }
            let run = Array(after.prefix(length))
            let repeated = said.indices.contains { start in
                start + 2 * length <= said.count
                    && Array(said[start..<(start + length)]) == run
                    && Array(said[(start + length)..<(start + 2 * length)]) == run
            }
            if !repeated { doubled.append(run.joined(separator: " ")) }
        }
        return doubled
    }

    // MARK: - Pieces

    private static func hasBoundary(_ piece: String) -> Bool {
        piece.hasPrefix(" ") || piece.hasPrefix("\u{2581}")
    }

    /// A piece that's nothing but punctuation once its boundary is stripped.
    static func isPunctuation(_ piece: String) -> Bool {
        let core = piece.replacingOccurrences(of: "\u{2581}", with: "").trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return false }
        return core.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }

    /// Whether the piece at `index` starts a word (FluidAudio's `startsWordPiece`).
    static func startsWord(_ pieces: [String], at index: Int) -> Bool {
        let piece = pieces[index]
        guard hasBoundary(piece) else { return false }
        if !isPunctuation(piece) { return true }
        let core = piece.replacingOccurrences(of: "\u{2581}", with: "").trimmingCharacters(in: .whitespaces)
        guard core == "'" || core == "\u{2019}" || core == "-", index + 1 < pieces.count else { return false }
        let next = pieces[index + 1]
        return !hasBoundary(next) && !isPunctuation(next)
    }

    /// FluidAudio's `wordCore`: lowercased, curly apostrophes straightened, whitespace and
    /// punctuation trimmed from both ends.
    static func core<S: Sequence>(_ pieces: S) -> String where S.Element == String {
        let joined = pieces.joined()
            .replacingOccurrences(of: "\u{2581}", with: " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
        let scalars = Array(joined.unicodeScalars)
        let isEdge: (Unicode.Scalar) -> Bool = {
            CharacterSet.whitespaces.contains($0) || CharacterSet.punctuationCharacters.contains($0)
        }
        guard let first = scalars.firstIndex(where: { !isEdge($0) }),
              let last = scalars.lastIndex(where: { !isEdge($0) })
        else { return "" }
        return String(String.UnicodeScalarView(scalars[first...last]))
    }
}
