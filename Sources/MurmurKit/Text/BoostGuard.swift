import Foundation

/// The last word on whether a vocabulary-boosting rewrite may stand.
///
/// The CTC rescorer compares a heard phrase with a dictionary term as one string, so a span
/// can pass on the strength of one word alone: "Claude. I've" scores 0.73 against
/// "Claude Code" because "claude" matches and the rest is short. That swallowed the next
/// word, across a sentence end. These checks look at the words one by one.
public enum BoostGuard {
    /// Each heard word must be at least this close to the term word it becomes, when the
    /// counts line up: "cloud code" → "Claude Code" scores 0.67 and 1.
    public static let wordSimilarity = 0.5
    /// Several heard words that become fewer term words ("and topic" → "Anthropic", 0.67).
    public static let joinedSimilarity = 0.6
    /// Fewer heard words than the term has: one word may only stand for two when it sounds
    /// like both ("CloudCode" → "Claude Code", 0.8), not when it is the first of them
    /// ("Claude" → "Claude Code", 0.6).
    public static let expandingSimilarity = 0.75
    /// How closely the fewer words must spell the term when a span is narrowed (`span`):
    /// "BirdTown Flow" out of "BirdTown Flow will" scores 1, "cloud code" out of "cloud code
    /// is" 0.8.
    public static let narrowedSimilarity = 0.8

    /// Punctuation that ends a clause. A term never spans one.
    private static let clauseEnders: Set<Character> = [".", ",", ";", ":", "!", "?", "…"]

    /// - Parameters:
    ///   - heard: the transcript's words the rewrite replaces, as written (with punctuation).
    ///   - term: the dictionary term it writes.
    public static func accepts(heard: [String], term: String) -> Bool {
        guard !heard.isEmpty else { return false }
        // A term never runs across "Claude. I've": only the last heard word may end a clause.
        for word in heard.dropLast() where word.last.map(clauseEnders.contains) == true {
            return false
        }

        let spoken = heard.map(normalized).filter { !$0.isEmpty }
        let written = words(of: term)
        guard !spoken.isEmpty, !written.isEmpty else { return false }

        // One word for one: the rescorer's own similarity gate already judged exactly this.
        if spoken.count == 1, written.count == 1 { return true }
        if spoken.count == written.count {
            return zip(spoken, written).allSatisfy { pair in
                PolishGuard.similarity(Array(pair.0), Array(pair.1)) >= wordSimilarity
            }
        }
        let joined = PolishGuard.similarity(Array(spoken.joined()), Array(written.joined()))
        return joined >= (spoken.count < written.count ? expandingSimilarity : joinedSimilarity)
    }

    /// Which of `heard` a rewrite to `term` replaces: all of them, fewer when the rescorer's
    /// span took in a neighbouring word, or `nil` when the rewrite mustn't stand at all.
    ///
    /// The rescorer can score "BirdTown Flow will" against "Birdtown Flow" higher than
    /// "BirdTown Flow" and rewrite all three words, dropping "will" (seen in CI). When the
    /// heard words outnumber the term's and leaving some out at either end spells the term
    /// better, and at least `narrowedSimilarity`, only those are replaced and the others stay.
    public static func span(heard: [String], term: String) -> Range<Int>? {
        let written = words(of: term)
        if heard.count > written.count, !written.isEmpty {
            let whole = fit(heard[...], written)
            var best: (range: Range<Int>, fit: Double)?
            for lower in 0..<heard.count {
                for upper in (lower + 1)...heard.count where upper - lower < heard.count {
                    let score = fit(heard[lower..<upper], written)
                    guard score >= narrowedSimilarity, score > whole,
                          accepts(heard: Array(heard[lower..<upper]), term: term)
                    else { continue }
                    // The closest spelling; of two equally close, the one keeping more words.
                    if let best, best.fit > score || (best.fit == score && best.range.count >= upper - lower) {
                        continue
                    }
                    best = (lower..<upper, score)
                }
            }
            if let best { return best.range }
        }
        return accepts(heard: heard, term: term) ? 0..<heard.count : nil
    }

    /// How closely `heard`, run together, spells `written` run together.
    private static func fit(_ heard: ArraySlice<String>, _ written: [String]) -> Double {
        let spoken = heard.map(normalized).joined()
        guard !spoken.isEmpty else { return 0 }
        return PolishGuard.similarity(Array(spoken), Array(written.joined()))
    }

    /// The term's words, normalized: "Claude Code" and "Claude-Code" are both claude, code.
    private static func words(of term: String) -> [String] {
        term
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Lowercased letters and digits only.
    static func normalized(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
