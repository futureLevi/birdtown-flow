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
        /// previous text has no punctuation of its own.
        public var leadingPunctuation: String
        /// The last kept word, for the next window's seam check. `nil` when nothing was kept.
        public var lastWord: TimedWord?
        /// The first word heard after the kept stretch, which this window leaves to the next
        /// one, for that window's seam check. `nil` for the tail, or when none was heard.
        public var nextWord: TimedWord?
        /// `tokens` as text, trimmed.
        public var text: String

        public init(
            tokens: [TimedToken] = [], leadingPunctuation: String = "", lastWord: TimedWord? = nil,
            nextWord: TimedWord? = nil, text: String = ""
        ) {
            self.tokens = tokens
            self.leadingPunctuation = leadingPunctuation
            self.lastWord = lastWord
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

    /// The words of one window that start inside `keep`.
    ///
    /// The two windows at a seam time a word near the cut a frame or two apart, so it can
    /// land on different sides of the cut in each. Both mistakes are caught by comparing the
    /// words either side of the cut: same core, starting within `seamTolerance`.
    ///
    /// - Parameters:
    ///   - tokens: the window's tokens, in order, timed on the recording's clock.
    ///   - keep: the window's kept stretch, in seconds.
    ///   - previous: the last word the previous window kept. A first kept word that's the same
    ///     word was heard twice across the cut, and is dropped.
    ///   - following: the first word the previous window heard after the cut, and so left to
    ///     this one (its `nextWord`). When this window hears that word just before the cut,
    ///     neither window would write it, so this one keeps it.
    public static func keep(
        _ tokens: [TimedToken], in keep: Range<Double>, after previous: TimedWord?, following: TimedWord? = nil
    ) -> Kept {
        let words = Self.words(tokens)
        var kept = words.filter { keep.contains($0.start) }
        if let first = kept.first, let previous, isSameWord(first, previous) {
            kept.removeFirst()
        }
        if let following, let before = words.last(where: { $0.start < keep.lowerBound }),
           isSameWord(before, following), !(previous.map { isSameWord(before, $0) } ?? false) {
            kept.insert(before, at: 0)
        }

        // Punctuation heard inside the kept stretch but before the first kept word, outside
        // any word this window keeps: it closes a word the previous window kept.
        let firstKept = kept.first?.tokens.lowerBound ?? tokens.count
        var leading = ""
        for token in tokens[..<firstKept] where keep.contains(token.start) && isPunctuation(token.text) {
            leading += token.text.trimmingCharacters(in: .whitespaces)
        }

        let keptTokens = kept.flatMap { tokens[$0.tokens] }
        let text = keptTokens.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return Kept(
            tokens: keptTokens, leadingPunctuation: leading, lastWord: kept.last,
            nextWord: words.first(where: { $0.start >= keep.upperBound }), text: text
        )
    }

    /// The same word heard by two windows: same core, starting within `seamTolerance`.
    private static func isSameWord(_ a: TimedWord, _ b: TimedWord) -> Bool {
        a.core == b.core && abs(a.start - b.start) <= seamTolerance + 1e-9
    }

    // MARK: - Joining

    /// The windows' texts as one transcript: single spaces between parts, a part's leading
    /// punctuation attached only where the text before it has none. Capitalisation is
    /// never changed.
    public static func join(_ parts: [Part]) -> String {
        var joined = ""
        for part in parts {
            let leading = part.leadingPunctuation.trimmingCharacters(in: .whitespaces)
            if !leading.isEmpty, let last = joined.last, !closingPunctuation.contains(last) {
                joined += leading
            }
            let text = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            joined += joined.isEmpty ? text : " " + text
        }
        return joined
    }

    /// Words written on both sides of a seam ("the the" across two parts) that `reference`
    /// (the same recording transcribed whole) doesn't repeat. For the speech smoke test.
    public static func doubledSeams(_ parts: [String], reference: String) -> [String] {
        let texts = parts.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }.filter { !$0.isEmpty }
        let said = reference.split(whereSeparator: \.isWhitespace).map { core(CollectionOfOne(String($0))) }
        var doubled: [String] = []
        for (before, after) in zip(texts, texts.dropFirst()) {
            let word = core(CollectionOfOne(before[before.count - 1]))
            guard !word.isEmpty, word == core(CollectionOfOne(after[0])) else { continue }
            let repeated = zip(said, said.dropFirst()).contains { $0 == word && $1 == word }
            if !repeated { doubled.append(word) }
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
