import Testing
@testable import MurmurKit

struct BoostGuardTests {
    @Test("Boost rewrites that keep to what was said", arguments: [
        (["cloud", "code"], "Claude Code"),
        (["and", "topic"], "Anthropic"),
        (["bird", "town"], "Birdtown"),
        (["CloudCode"], "Claude Code"),
        (["cloud-code."], "Claude Code"),
        (["parakeet,"], "Parakeet"),
        (["shivon"], "Siobhan"),
    ])
    func accepted(heard: [String], term: String) {
        #expect(BoostGuard.accepts(heard: heard, term: term))
    }

    @Test("Boost rewrites that swallow or invent words", arguments: [
        // Across a sentence end, taking the next word with it (seen in History).
        (["Claude.", "I've"], "Claude Code"),
        (["Claude.", "Um"], "Claude Code"),
        // The same without the period: "I've" sounds nothing like "Code".
        (["Claude", "I've"], "Claude Code"),
        // One word standing in for two it only half sounds like.
        (["Claude"], "Claude Code"),
        ([], "Claude Code"),
    ])
    func rejected(heard: [String], term: String) {
        #expect(!BoostGuard.accepts(heard: heard, term: term))
    }

    @Test("A span that took in a neighbouring word only replaces the term's words", arguments: [
        // Seen in CI: "Finally, Birdtown Flow will be part of the release" lost "will".
        (["BirdTown", "Flow", "will"], "Birdtown Flow", 0..<2),
        (["Finally,", "BirdTown", "Flow"], "Birdtown Flow", 1..<3),
        (["BirdTown", "Flow,", "will"], "Birdtown Flow", 0..<2),
        (["cloud", "code", "is"], "Claude Code", 0..<2),
        (["the", "bird", "town"], "Birdtown", 1..<3),
    ])
    func narrowed(heard: [String], term: String, replaced: Range<Int>) {
        #expect(BoostGuard.span(heard: heard, term: term) == replaced)
    }

    @Test("Spans that are all the term keep every word", arguments: [
        (["cloud", "code"], "Claude Code"),
        // Neither "topic" nor "and" alone spells "Anthropic" as well as both together.
        (["and", "topic"], "Anthropic"),
        (["and", "thropic"], "Anthropic"),
        (["bird", "town"], "Birdtown"),
        (["get", "hub"], "GitHub"),
        (["CloudCode"], "Claude Code"),
        (["parakeet,"], "Parakeet"),
    ])
    func whole(heard: [String], term: String) {
        #expect(BoostGuard.span(heard: heard, term: term) == 0..<heard.count)
    }

    @Test("Spans the guard turns down stay turned down", arguments: [
        (["Claude.", "I've"], "Claude Code"),
        (["Claude", "I've"], "Claude Code"),
        (["Claude.", "I've", "been"], "Claude Code"),
        (["Claude"], "Claude Code"),
        ([], "Claude Code"),
    ])
    func vetoed(heard: [String], term: String) {
        #expect(BoostGuard.span(heard: heard, term: term) == nil)
    }
}
