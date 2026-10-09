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
}
