import Foundation
import MurmurDictionary

/// History's Replacements: which dictionary terms each step of a dictation wrote in, and
/// what was there before.
public enum Replacements {
    /// Every step's changes, labelled with the step, in the order the steps ran: boosting
    /// (on the audio), then polish, then the dictionary's exact corrections. The same pair
    /// from the same step is one row, with the counts added.
    public static func combined(
        boost: [AppliedCorrection], polish: [AppliedCorrection], dictionary: [AppliedCorrection]
    ) -> [AppliedCorrection] {
        let labeled = boost.map { $0.labeled(.boost) }
            + polish.map { $0.labeled(.polish) }
            + dictionary.map { $0.labeled(.dictionary) }
        return merged(labeled)
    }

    /// One entry per pair and step, with the counts added, in first-seen order.
    public static func merged(_ corrections: [AppliedCorrection]) -> [AppliedCorrection] {
        var merged: [AppliedCorrection] = []
        for correction in corrections {
            if let index = merged.firstIndex(where: {
                $0.from == correction.from && $0.to == correction.to && $0.source == correction.source
            }) {
                let seen = merged[index]
                merged[index] = AppliedCorrection(
                    from: seen.from, to: seen.to, count: seen.count + correction.count, source: seen.source)
            } else {
                merged.append(correction)
            }
        }
        return merged
    }

    /// The vocabulary terms a polish wrote in place of other words: "cloud code" became
    /// "Claude Code". Found by lining up the words before and after; only an edited stretch
    /// that now holds a term, spelled exactly as the dictionary has it, counts. A term the
    /// model added where nothing was replaced isn't listed (`PolishGuard` judges those).
    ///
    /// - Parameters:
    ///   - original: the text polish was given.
    ///   - polished: the text it returned and the guard accepted.
    public static func polish(original: String, polished: String, vocabulary: [String]) -> [AppliedCorrection] {
        // Longer terms first, so "Claude Code" is credited rather than a term inside it.
        let terms = vocabulary
            .map { term in (term: term, words: tokens(term).map(\.text)) }
            .filter { !$0.words.isEmpty }
            .sorted { $0.words.count > $1.words.count }
        guard !terms.isEmpty else { return [] }

        let before = tokens(original)
        let after = tokens(polished)
        var found: [AppliedCorrection] = []
        for edit in edits(from: before.map(\.text), to: after.map(\.text)) {
            let added = edit.added.map { after[$0].text }
            var hit: (term: String, words: [String], start: Int)?
            for term in terms {
                if let start = added.firstRun(of: term.words) {
                    hit = (term.term, term.words, start)
                    break
                }
            }
            guard let match = hit else { continue }
            let start = match.start
            // What it replaced, less the words around it that only changed case ("so" became
            // "So" at the start of the sentence) and the fillers polish dropped beside it.
            let leading = added[..<start]
            let trailing = added[(start + match.words.count)...]
            var removed = edit.removed[...]
            dropFillers(&removed, in: before)
            for word in leading {
                guard let head = removed.first, before[head].text.lowercased() == word.lowercased() else { break }
                removed.removeFirst()
            }
            for word in trailing.reversed() {
                guard let tail = removed.last, before[tail].text.lowercased() == word.lowercased() else { break }
                removed.removeLast()
            }
            dropFillers(&removed, in: before)
            guard let first = removed.first, let last = removed.last else { continue }
            let from = String(original[before[first].range.lowerBound..<before[last].range.upperBound])
            guard from != match.term else { continue }
            found.append(AppliedCorrection(from: from, to: match.term, count: 1, source: .polish))
        }
        return merged(found)
    }

    // MARK: - Words

    struct Token {
        var text: String
        var range: Range<String.Index>
    }

    /// Words with their place in `text`: letters and digits, with apostrophes inside a word
    /// ("don't") kept.
    static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var start: String.Index?
        var index = text.startIndex
        func isWordCharacter(_ character: Character) -> Bool { character.isLetter || character.isNumber }
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            let joinsWord = (character == "'" || character == "’") && start != nil
                && next < text.endIndex && isWordCharacter(text[next])
            if isWordCharacter(character) || joinsWord {
                if start == nil { start = index }
            } else if let begun = start {
                tokens.append(Token(text: String(text[begun..<index]), range: begun..<index))
                start = nil
            }
            index = next
        }
        if let begun = start {
            tokens.append(Token(text: String(text[begun...]), range: begun..<text.endIndex))
        }
        return tokens
    }

    /// Takes filler words off both ends of `positions`.
    private static func dropFillers(_ positions: inout ArraySlice<Int>, in words: [Token]) {
        func isFiller(_ position: Int) -> Bool { TextPipeline.fillerWords.contains(words[position].text.lowercased()) }
        while let head = positions.first, isFiller(head) { positions.removeFirst() }
        while let tail = positions.last, isFiller(tail) { positions.removeLast() }
    }

    /// One stretch where the two word lists differ: the positions taken out of the first and
    /// put into the second.
    struct Edit: Equatable {
        var removed: [Int]
        var added: [Int]
    }

    /// The stretches where `after` differs from `before`, word for word and case included,
    /// in order. Words both share in the same order (a longest common subsequence) separate
    /// the stretches.
    static func edits(from before: [String], to after: [String]) -> [Edit] {
        var removedAt = Set<Int>()
        var insertedAt = Set<Int>()
        for change in after.difference(from: before) {
            switch change {
            case .remove(let offset, _, _): removedAt.insert(offset)
            case .insert(let offset, _, _): insertedAt.insert(offset)
            }
        }
        var edits: [Edit] = []
        var current = Edit(removed: [], added: [])
        var i = 0
        var j = 0
        while i < before.count || j < after.count {
            if i < before.count, removedAt.contains(i) {
                current.removed.append(i)
                i += 1
            } else if j < after.count, insertedAt.contains(j) {
                current.added.append(j)
                j += 1
            } else {
                // A word both keep ends the stretch.
                if !current.removed.isEmpty || !current.added.isEmpty { edits.append(current) }
                current = Edit(removed: [], added: [])
                i += 1
                j += 1
            }
        }
        if !current.removed.isEmpty || !current.added.isEmpty { edits.append(current) }
        return edits
    }
}

extension Array where Element == String {
    /// Where `run` first appears here as consecutive elements.
    fileprivate func firstRun(of run: [String]) -> Int? {
        guard !run.isEmpty, run.count <= count else { return nil }
        return (0...(count - run.count)).first { Array(self[$0..<($0 + run.count)]) == run }
    }
}
