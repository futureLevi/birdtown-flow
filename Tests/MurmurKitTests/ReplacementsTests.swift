import Foundation
import MurmurDictionary
import Testing
@testable import MurmurKit

struct ReplacementsTests {
    @Test("Polish replacements: the words a term took the place of", arguments: [
        ("so cloud code is great", "So Claude Code is great.", ["Claude Code"], "cloud code", "Claude Code"),
        // Fillers dropped beside the term, and a word that only changed case, aren't part of it.
        ("um the github repo", "The GitHub repo.", ["GitHub"], "github", "GitHub"),
        ("push it to github", "Push it to GitHub.", ["GitHub"], "github", "GitHub"),
        ("ask and topic about it", "Ask Anthropic about it.", ["Claude Code", "Anthropic"], "and topic", "Anthropic"),
        // A longer term is credited before one inside it.
        ("open cloud code", "Open Claude Code.", ["Claude", "Claude Code"], "cloud code", "Claude Code"),
    ])
    func polishReplacement(original: String, polished: String, vocabulary: [String], from: String, to: String) {
        let found = Replacements.polish(original: original, polished: polished, vocabulary: vocabulary)
        #expect(found == [AppliedCorrection(from: from, to: to, count: 1, source: .polish)])
    }

    @Test("Polish replacements: nothing when no term was written over other words", arguments: [
        // Already right.
        ("Claude Code is great", "Claude Code is great.", ["Claude Code"]),
        // Only fillers and punctuation changed.
        ("um so we we ship it", "So we ship it.", ["Claude Code"]),
        // Added where nothing was replaced: PolishGuard's call, not a replacement.
        ("send it", "Send it, Anthropic.", ["Anthropic"]),
        // No vocabulary.
        ("cloud code", "Claude Code", [String]()),
    ])
    func noPolishReplacement(original: String, polished: String, vocabulary: [String]) {
        #expect(Replacements.polish(original: original, polished: polished, vocabulary: vocabulary).isEmpty)
    }

    @Test("The same polish replacement twice is one row")
    func polishCounts() {
        let found = Replacements.polish(
            original: "cloud code and then cloud code again", polished: "Claude Code and then Claude Code again.",
            vocabulary: ["Claude Code"])
        #expect(found == [AppliedCorrection(from: "cloud code", to: "Claude Code", count: 2, source: .polish)])
    }

    @Test("Each step's changes are labelled, and merged only within a step")
    func combined() {
        let pair = AppliedCorrection(from: "cloud code", to: "Claude Code", count: 1)
        let rows = Replacements.combined(
            boost: [pair, AppliedCorrection(from: "and topic", to: "Anthropic", count: 1), pair],
            polish: [AppliedCorrection(from: "github", to: "GitHub", count: 1, source: .polish)],
            dictionary: [pair])
        #expect(rows == [
            AppliedCorrection(from: "cloud code", to: "Claude Code", count: 2, source: .boost),
            AppliedCorrection(from: "and topic", to: "Anthropic", count: 1, source: .boost),
            AppliedCorrection(from: "github", to: "GitHub", count: 1, source: .polish),
            AppliedCorrection(from: "cloud code", to: "Claude Code", count: 1, source: .dictionary),
        ])
    }

    @Test("History saved before steps were labelled still loads, and labels round-trip")
    func codable() throws {
        let old = try JSONDecoder().decode(
            AppliedCorrection.self, from: Data(#"{"from":"board","to":"BTAR","count":2}"#.utf8))
        #expect(old == AppliedCorrection(from: "board", to: "BTAR", count: 2))
        #expect(old.source == nil)

        let labeled = old.labeled(.boost)
        let decoded = try JSONDecoder().decode(AppliedCorrection.self, from: JSONEncoder().encode(labeled))
        #expect(decoded.source == .boost)
    }

    @Test("Words keep their place and inner apostrophes")
    func tokens() {
        let text = "Don't use Node.js, um, 'quoted'"
        #expect(Replacements.tokens(text).map(\.text) == ["Don't", "use", "Node", "js", "um", "quoted"])
        #expect(Replacements.tokens(text).allSatisfy { text[$0.range] == $0.text })
    }
}
