import Foundation
import Testing
@testable import MurmurKit

/// "Item 7 the team looked at this again…." with exactly `words` words.
private func sentence(_ index: Int, words: Int, opening: String = "Item") -> String {
    let filler = [
        "the", "team", "looked", "at", "this", "again", "on", "the", "morning", "call", "and", "noted",
        "a", "few", "small", "things", "to", "fix", "before", "launch",
    ]
    var parts = [opening, "\(index)"]
    var next = 0
    while parts.count < words {
        parts.append(filler[next % filler.count])
        next += 1
    }
    return parts.prefix(words).joined(separator: " ") + "."
}

/// Sentences of varied length, about `total` words, joined with single spaces.
private func sentences(from start: Int = 0, total: Int) -> [String] {
    let lengths = [12, 9, 17, 14, 21, 8, 15, 11, 19, 10]
    var result: [String] = []
    var words = 0
    var index = start
    while words < total {
        let length = lengths[index % lengths.count]
        result.append(sentence(index, words: length))
        words += length
        index += 1
    }
    return result
}

private func wordCount(_ text: String) -> Int {
    text.split { $0.isWhitespace }.count
}

/// About 800 words where a part could end at a correction, a continuation, a list, a
/// paragraph break and an abbreviation.
private let mixed: String = {
    // 148 words, then sentence ends at 154 (before "No"), 157 (before "And") and 162.
    var parts = sentences(total: 140)
    parts += ["Let's move the launch to Thursday.", "No wait, Friday.", "And tell the team tonight."]
    // 136 words, then 143, 147, 151 (before "Third") and 155.
    parts += sentences(from: 100, total: 130)
    parts += ["We need three things for the trip.", "First, sunscreen for everyone.", "Second, a towel each.",
              "Third, plenty of snacks."]
    // 96 words (before "So"), then a paragraph break at 100.
    parts += sentences(from: 200, total: 90)
    parts.append("So that's the plan.\n\nThe budget is next.")
    // 147 words, then "Dr." at 151 and "e.g." at 153.
    parts += (500..<513).map { sentence($0, words: 11) }
    parts.append("Send it to Dr. Smith, e.g. by email.")
    parts += sentences(from: 400, total: 220)
    return parts.joined(separator: " ")
}()

@Suite("PolishChunker")
struct PolishChunkerTests {
    @Test("Under 250 words is one part: the text itself")
    func shortText() {
        let text = sentences(total: 240).joined(separator: " ")
        #expect(wordCount(text) < PolishChunker.minimumWords)
        #expect(PolishChunker.chunks(text) == [PolishChunk(text: text, separatorBefore: "", context: nil, continues: false)])
        #expect(PolishChunker.chunks(text, closedOnly: true).isEmpty)
    }

    @Test("A long text splits into parts of 90 to 260 words at sentence ends")
    func longText() throws {
        let text = sentences(total: 900).joined(separator: " ")
        let chunks = PolishChunker.chunks(text)
        #expect(chunks.count >= 4)
        for chunk in chunks.dropLast() {
            #expect((PolishChunker.minWords...PolishChunker.maxWords).contains(wordCount(chunk.text)))
            #expect(chunk.text.hasSuffix("."))
            #expect(chunk.continues)
        }
        let last = try #require(chunks.last)
        #expect(!last.continues)
        #expect(wordCount(last.text) <= PolishChunker.maxWords)
        // Nothing is lost or added between the parts.
        #expect(PolishChunker.join(chunks.map(\.text), chunks: chunks, style: .formal) == text)
    }

    @Test("A text with nowhere to split stays whole")
    func noSentenceEnds() {
        let text = Array(repeating: "and then we kept going", count: 80).joined(separator: " ")
        #expect(PolishChunker.chunks(text) == [PolishChunk(text: text, separatorBefore: "", context: nil, continues: false)])
    }

    @Test("A correction stays with what it corrects", arguments: 6...14)
    func correctionNotSplit(leading: Int) {
        let parts = (0..<leading).map { sentence($0, words: 12) }
            + ["Let's move the launch to Thursday.", "No wait, Friday."] + sentences(from: 50, total: 300)
        let chunks = PolishChunker.chunks(parts.joined(separator: " "))
        #expect(chunks.count > 1)
        #expect(!chunks.contains { $0.text.hasSuffix("Thursday.") })
        #expect(!chunks.contains { $0.text.hasPrefix("No wait") })
    }

    @Test("A dictated list stays in one part", arguments: 6...14)
    func listNotSplit(leading: Int) {
        let parts = (0..<leading).map { sentence($0, words: 12) }
            + ["We need three things for the trip.", "First, sunscreen.", "Second, a towel.", "Third, snacks."]
            + sentences(from: 50, total: 300)
        let chunks = PolishChunker.chunks(parts.joined(separator: " "))
        #expect(chunks.count > 1)
        for opening in ["First", "Second", "Third"] {
            #expect(!chunks.contains { $0.text.hasPrefix(opening) })
        }
    }

    @Test("A paragraph break is where a part ends once it has 90 words")
    func paragraphPreferred() {
        let first = (0..<8).map { sentence($0, words: 12) }.joined(separator: " ")
        let rest = sentences(from: 20, total: 400).joined(separator: " ")
        let chunks = PolishChunker.chunks(first + "\n\n" + rest)
        #expect(chunks.first?.text == first)
        #expect(chunks.dropFirst().first?.separatorBefore == "\n\n")

        // Shorter than that, the break is just a sentence end.
        let short = (0..<6).map { sentence($0, words: 12) }.joined(separator: " ")
        let later = PolishChunker.chunks(short + "\n\n" + rest)
        #expect(later.first.map { wordCount($0.text) > wordCount(short) } == true)
        #expect(later.first?.text.hasPrefix(short + "\n\n") == true)
    }

    @Test("Continuations wait until 260 words, corrections and list items until 400")
    func cueLimits() throws {
        let continuing = (0..<60).map { sentence($0, words: 10, opening: "And") }.joined(separator: " ")
        let first = try #require(PolishChunker.chunks(continuing).first)
        #expect(wordCount(first.text) == 260)

        let correcting = (0..<60).map { sentence($0, words: 10, opening: "Actually") }.joined(separator: " ")
        let firstCorrected = try #require(PolishChunker.chunks(correcting).first)
        #expect(wordCount(firstCorrected.text) == 400)
    }

    @Test("Finished parts of a growing text are the parts the whole text gets")
    func prefixStability() throws {
        let full = PolishChunker.chunks(mixed)
        try #require(full.count >= 5)
        // Each part ends just past the place it was held back from.
        #expect(full[0].text.hasSuffix("Thursday. No wait, Friday. And tell the team tonight."))
        #expect(full[1].text.hasSuffix("Second, a towel each. Third, plenty of snacks."))
        #expect(full[2].text.hasSuffix("So that's the plan."))
        #expect(full[3].separatorBefore == "\n\n")
        #expect(full[3].text.hasSuffix("Send it to Dr. Smith, e.g. by email."))

        // At every sentence end…
        var prefixes: [String] = []
        var cursor = mixed.startIndex
        while let end = mixed[cursor...].firstIndex(where: { ".!?".contains($0) }) {
            prefixes.append(String(mixed[...end]))
            cursor = mixed.index(after: end)
        }
        // …at every word, and partway through words.
        let words = mixed.split(separator: " ")
        for count in 1...words.count {
            let prefix = words.prefix(count).joined(separator: " ")
            prefixes.append(prefix)
            if count % 3 == 0, let last = words[count - 1].first {
                prefixes.append(words.prefix(count - 1).joined(separator: " ") + " " + String(last))
            }
        }
        var largest = 0
        for prefix in prefixes {
            let closed = PolishChunker.chunks(prefix, closedOnly: true)
            #expect(Array(full.prefix(closed.count)) == closed, "prefix of \(wordCount(prefix)) words")
            #expect(closed.allSatisfy { $0.continues })
            largest = max(largest, closed.count)
        }
        #expect(largest == full.count - 1)
    }

    @Test("A part isn't finished until the first word after it is known")
    func undecidedBoundary() {
        // One part of 156 words, then one that could end after "Thursday." at 150.
        let first = (0..<13).map { sentence($0, words: 12) }
        let second = (20..<32).map { sentence($0, words: 12) } + ["Let's move the launch to Thursday."]
        let text = (first + second).joined(separator: " ")
        // "N" may yet be "No", which keeps the correction with it.
        #expect(PolishChunker.chunks(text + " N", closedOnly: true).count == 1)
        #expect(PolishChunker.chunks(text + " No wait, Friday.", closedOnly: true).count == 1)
        #expect(PolishChunker.chunks(text + " Nobody minded.", closedOnly: true).count == 2)
    }

    @Test("Context is the end of the part before, at most 60 words")
    func context() throws {
        let chunks = PolishChunker.chunks(mixed)
        #expect(chunks.first?.context == nil)
        for (previous, chunk) in zip(chunks, chunks.dropFirst()) {
            let context = try #require(chunk.context)
            #expect(wordCount(context) <= PolishChunker.contextWords)
            #expect(wordCount(context) > 0)
            #expect(previous.text.hasSuffix(context))
        }

        // A last sentence longer than that gives its last 60 words.
        let long = sentence(0, words: 70, opening: "Overall")
        let text = (sentences(total: 100) + [long] + sentences(from: 30, total: 200)).joined(separator: " ")
        let split = PolishChunker.chunks(text)
        let second = try #require(split.dropFirst().first)
        #expect(split.first?.text.hasSuffix(long) == true)
        #expect(wordCount(second.context ?? "") == PolishChunker.contextWords)
        #expect(long.hasSuffix(second.context ?? "-"))
    }

    @Test("Joining puts back the paragraph break, a dropped period and an excited part's \"!\"")
    func join() throws {
        let first = (0..<8).map { sentence($0, words: 12) }.joined(separator: " ")
        let text = first + "\n\n" + sentences(from: 20, total: 400).joined(separator: " ")
        let chunks = PolishChunker.chunks(text)
        try #require(chunks.count >= 3)

        var outputs = chunks.map(\.text)
        outputs[0].removeLast()
        outputs[1] = String(outputs[1].dropLast()) + "!"
        #expect(PolishChunker.join(outputs, chunks: chunks, style: .excited) == text)
        // Another style keeps an exclamation mark the model chose.
        #expect(PolishChunker.join(outputs, chunks: chunks, style: .casual).contains("!"))

        // A part that trails off with a comma ends as dictated; the last part is left to finalize.
        outputs[1] = String(chunks[1].text.dropLast()) + ","
        let last = outputs.count - 1
        outputs[last] = String(outputs[last].dropLast()) + "!"
        let joined = PolishChunker.join(outputs, chunks: chunks, style: .excited)
        #expect(joined.hasSuffix("!"))
        #expect(joined.dropLast() == text.dropLast())

        // Whitespace around a model's reply doesn't double the separators.
        let padded = chunks.map { "\n " + $0.text + " \n" }
        #expect(PolishChunker.join(padded, chunks: chunks, style: .formal) == text)
    }

    @Test("Abbreviations and initials don't end a part")
    func abbreviations() {
        for leading in 8...14 {
            let parts = (0..<leading).map { sentence($0, words: 12) }
                + ["We asked Dr. Smith and J. R. Jones about apps, e.g. Slack in the U.S. Army."]
                + sentences(from: 50, total: 300)
            let text = parts.joined(separator: " ")
            let chunks = PolishChunker.chunks(text)
            for ending in ["Dr.", "J.", "R.", "e.g.", "U.S."] {
                #expect(!chunks.contains { $0.text.hasSuffix(ending) })
            }
            #expect(PolishChunker.join(chunks.map(\.text), chunks: chunks, style: .formal) == text)
        }
    }

    @Test("Sentence ends", arguments: [
        ("done.", false, true), ("done!", false, true), ("done?”", false, true), ("then...", false, true),
        ("done…", false, true), ("Dr.", false, false), ("e.g.", false, false), ("U.S.", false, false),
        ("J.", false, false), ("3.5", false, false), ("done", false, false), ("(Dr.)", false, false), ("end.)", false, true),
        ("2.", true, false), ("2.", false, true), ("Mr.", false, false), ("Jan.", false, false),
    ])
    func sentenceEnds(token: String, startsSegment: Bool, expected: Bool) {
        #expect(PolishChunker.endsSentence(Substring(token), startsSegment: startsSegment) == expected)
    }

    @Test("Cues", arguments: [
        ("No,", PolishChunker.Cue.strong), ("Wait", .strong), ("Actually,", .strong), ("Second,", .strong),
        ("Secondly,", .strong), ("2nd", .strong), ("2.", .strong), ("-", .strong), ("Finally,", .strong),
        ("And", .weak), ("So", .weak), ("“But", .weak), ("The", .none), ("Nobody", .none), ("Item", .none),
    ])
    func cues(token: String, expected: PolishChunker.Cue) {
        #expect(PolishChunker.cue(Substring(token)) == expected)
    }

    @Test("Parts polished at once, by provider", arguments: [
        (PolishProvider.anthropic, false, 4), (.openAICompatible, false, 3), (.openAICompatible, true, 1),
        (.claudeCode, false, 3), (.appleIntelligence, false, 1), (.off, false, 1),
    ])
    func concurrency(provider: PolishProvider, local: Bool, expected: Int) {
        #expect(PolishChunker.concurrency(for: provider, localEndpoint: local) == expected)
    }
}
