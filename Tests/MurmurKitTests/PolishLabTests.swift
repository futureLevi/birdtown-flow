import Foundation
import Testing
@testable import MurmurKit

@Suite("Polish Lab")
@MainActor
struct PolishLabTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lab-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("lab.json")
    }

    @Test("A new Lab starts with the two built-in prompts, used for nothing yet")
    func starters() {
        let store = PolishLabStore(fileURL: tempFile())
        #expect(store.configurations.map(\.name) == ["Filler words only", "Full polish"])
        #expect(store.configurations.allSatisfy { $0.provider == .claudeCode && $0.effort == .low })
        #expect(store.configurations[0].instructions.contains("Remove only"))
        #expect(store.configurations[1].instructions.contains("copy editor"))
        #expect(!store.hasAssignments)
        #expect(store.configuration(for: .casual) == nil)
    }

    @Test("Each style belongs to at most one configuration; taking one moves it")
    func exclusiveStyles() throws {
        let store = PolishLabStore(preview: PolishLabState(configurations: PolishConfiguration.starters()))
        let light = store.configurations[0].id, full = store.configurations[1].id
        store.setStyles([.casual, .veryCasual], for: light)
        store.setStyles([.formal, .casual], for: full)
        #expect(store.styles(for: light) == [.veryCasual])
        #expect(store.styles(for: full) == [.formal, .casual])
        #expect(store.configuration(for: .casual)?.id == full)
        #expect(store.configuration(for: .excited) == nil)

        // Unticking gives a style back to Settings.
        store.setStyles([.formal], for: full)
        #expect(store.configuration(for: .casual) == nil)

        // Deleting frees its styles too.
        store.delete(id: full)
        #expect(store.configuration(for: .formal) == nil)
        #expect(store.styles(for: light) == [.veryCasual])
    }

    @Test("Duplicates get a distinct name and no styles")
    func duplicate() throws {
        let store = PolishLabStore(preview: PolishLabState(configurations: PolishConfiguration.starters()))
        let original = store.configurations[0]
        store.setStyles([.casual], for: original.id)
        let copy = try #require(store.duplicate(id: original.id))
        let again = try #require(store.duplicate(id: original.id))
        #expect(copy.name == "Filler words only copy")
        #expect(again.name == "Filler words only copy 2")
        #expect(copy.instructions == original.instructions)
        #expect(store.styles(for: copy.id).isEmpty)
        #expect(store.configurations[1].id == again.id || store.configurations[1].id == copy.id)
    }

    @Test("Edits and assignments survive a relaunch")
    func persistence() throws {
        let url = tempFile()
        let first = PolishLabStore(fileURL: url)
        var edited = first.configurations[0]
        edited.name = "Filler v2"
        edited.effort = .medium
        edited.instructions = "Only remove um."
        first.update(edited)
        first.setStyles([.excited], for: edited.id)

        let second = PolishLabStore(fileURL: url)
        let loaded = try #require(second.configuration(id: edited.id))
        #expect(loaded.name == "Filler v2")
        #expect(loaded.effort == .medium)
        #expect(loaded.instructions == "Only remove um.")
        #expect(second.configuration(for: .excited)?.id == edited.id)
    }

    @Test("An unreadable Lab file is set aside, not overwritten")
    func quarantine() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = PolishLabStore(fileURL: url)
        #expect(store.configurations.count == 2)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(siblings.count == 2)
    }

    @Test("A configuration's instructions replace the built-in prompt")
    func instructionsOverride() {
        var request = PolishRequest(text: "um hi", style: .casual, category: .work, appName: "Slack", vocabulary: [])
        request.instructions = "  Only remove um.  "
        #expect(PolishPrompt.system(for: request) == "Only remove um.")
        request.instructions = "   "
        #expect(PolishPrompt.system(for: request).contains("copy editor"))
    }

    @Test("Placeholders are filled per dictation")
    func placeholders() {
        var request = PolishRequest(
            text: "um hi", style: .veryCasual, category: .work, appName: "Slack", vocabulary: ["Birdtown", "BTA"])
        request.instructions = "Style: {{style}}\nTo: {{destination}}\nTerms: {{vocabulary}}\nKeep {{unknown}}."
        let prompt = PolishPrompt.system(for: request)
        #expect(prompt.contains("Style: Very casual. All lowercase"))
        #expect(prompt.contains("To: Slack, a work chat app."))
        #expect(prompt.contains("Terms: Birdtown, BTA"))
        #expect(prompt.contains("Keep {{unknown}}."))

        request.vocabulary = []
        #expect(PolishPrompt.system(for: request).contains("Terms: None."))
    }

    @Test("The starters say exactly what the built-in prompts say")
    func startersMatchBuiltIns() {
        let starters = PolishConfiguration.starters()
        for style in WritingStyle.allCases {
            var request = PolishRequest(
                text: "um hi", style: style, category: .email, appName: "Mail", vocabulary: ["Birdtown"])
            let builtIn = PolishPrompt.system(for: request)
            request.instructions = starters[1].instructions
            #expect(PolishPrompt.system(for: request) == builtIn)

            request.instructions = nil
            request.level = .fillerWords
            let light = PolishPrompt.system(for: request)
            request.instructions = starters[0].instructions
            #expect(PolishPrompt.system(for: request) == light)
        }
    }

    @Test("New configurations get free names; a saved copy keeps the edits and leaves the original")
    func newAndCopies() throws {
        let store = PolishLabStore(preview: PolishLabState(configurations: PolishConfiguration.starters()))
        let first = store.addUntitled()
        let second = store.addUntitled()
        #expect(first.name == "Untitled")
        #expect(second.name == "Untitled 2")

        let original = store.configurations[0]
        var draft = original
        draft.instructions = "Only remove um."
        let copy = store.duplicate(draft)
        #expect(copy.name == "Filler words only copy")
        #expect(copy.instructions == "Only remove um.")
        #expect(store.configurations[1].id == copy.id)
        #expect(store.configuration(id: original.id)?.instructions == original.instructions)
        #expect(copy.hasSameSetup(as: draft) == false)
        var renamed = draft
        renamed.name = copy.name
        #expect(copy.hasSameSetup(as: renamed))
    }

    @Test("A Lab file from an older build, missing newer fields, still opens")
    func olderFile() throws {
        let id = UUID()
        let json = """
            {"configurations":[{"id":"\(id.uuidString)","name":"Old","provider":"anthropic","instructions":"Be brief."}]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PolishLabState.self, from: Data(json.utf8))
        let config = try #require(state.configurations.first)
        #expect(config.id == id)
        #expect(config.notes == "")
        #expect(config.model == "claude-haiku-5-5")
        #expect(config.effort == .standard)
        #expect(state.assignments.isEmpty)
    }

    @Test("Explicit effort wins; model default sends none")
    func explicitEffort() throws {
        let request = PolishRequest(text: "um hi", style: .casual, category: .work, appName: nil, vocabulary: [])
        func config(_ effort: PolishEffort?) throws -> [String: Any]? {
            let body = try AnthropicClient(apiKey: "k", effort: effort).makeRequest(for: request).httpBody ?? Data()
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            return json?["output_config"] as? [String: Any]
        }
        #expect(try config(.high)?["effort"] as? String == "high")
        #expect(try config(.standard) == nil)
        #expect(try config(nil)?["effort"] as? String == "low")
    }

    @Test("Summaries name the provider, model and effort")
    func summary() {
        let config = PolishConfiguration.starters()[0]
        #expect(config.summary == "Claude Code · claude-haiku-5-5 · Low effort")
        var apple = config
        apple.provider = .appleIntelligence
        #expect(apple.summary == "Apple Intelligence")
        var api = config
        api.provider = .anthropic
        api.effort = .standard
        #expect(api.summary == "Claude API · claude-haiku-5-5 · Default effort")
    }
}

@Suite("WordDiff")
struct WordDiffTests {
    @Test("Removed filler shows as removed; punctuation and case changes don't count")
    func fillerRemoval() {
        let segments = WordDiff.diff(
            original: "So um I was like thinking we could, you know, go",
            revised: "So I was thinking we could go.")
        #expect(segments == [
            .same("So"), .removed("um"), .same("I was"), .removed("like"), .same("thinking we could"),
            .removed("you know,"), .same("go."),
        ])
        let counts = WordDiff.counts(original: "So um I was like thinking", revised: "So I was thinking")
        #expect(counts.removed == 2)
        #expect(counts.added == 0)
    }

    @Test("Added words and a dropped phrase are both visible")
    func addedAndDropped() {
        let counts = WordDiff.counts(
            original: "put the kids down and then do this and then go to work",
            revised: "put the kids down and then go to work, sadly")
        // "and then do this": four words, whichever "and then" the diff keeps.
        #expect(counts.removed == 4)
        #expect(counts.added == 1)
    }

    @Test("Curly and straight apostrophes match")
    func apostrophes() {
        #expect(WordDiff.counts(original: "I'm here", revised: "I\u{2019}m here") == (0, 0))
    }

    @Test("Empty sides")
    func empty() {
        #expect(WordDiff.diff(original: "", revised: "") == [])
        #expect(WordDiff.diff(original: "hello there", revised: "") == [.removed("hello there")])
        #expect(WordDiff.diff(original: "", revised: "hi") == [.added("hi")])
    }
}
