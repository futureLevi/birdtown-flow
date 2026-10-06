import Foundation
import MurmurDictionary
import Testing
@testable import MurmurKit

@Suite("TextPipeline.prepare")
struct PrepareTests {
    @Test("Fillers", arguments: [
        ("Um, I think we should go.", "I think we should go."),
        ("Uh so I was thinking.", "So I was thinking."),
        ("Um, uh, so, I was thinking.", "So, I was thinking."),
        ("So, um, I was thinking.", "So, I was thinking."),
        ("I went to the, uh, store.", "I went to the store."),
        ("I think um we should go.", "I think we should go."),
        ("I think um, we should go.", "I think we should go."),
        ("We should go, hmm.", "We should go."),
        ("Okay. Um. Let's go.", "Okay. Let's go."),
        ("Erm, ah, umm, uhh, mm, uhm, hmm, er, fine.", "Fine."),
        ("Ummm, yes.", "Yes."),
        ("Hello\num, thanks", "Hello\nThanks"),
        ("Um.", ""),
    ])
    func fillers(input: String, expected: String) {
        #expect(TextPipeline.prepare(input) == expected)
    }

    @Test("Fillers never inside words or acronyms", arguments: [
        "Grab an umbrella, there was an error.",
        "The hummus is ahead of the ermine.",
        "We went to the ER last night.",
        "Mm-hmm, that works.",
        "Uh-huh, sounds right.",
        "Use a 5 mm screw.",
        "I want a cat.",
    ])
    func fillersLeaveWordsAlone(input: String) {
        #expect(TextPipeline.prepare(input) == input)
    }

    @Test("Filler removal can be turned off")
    func fillersOff() {
        let input = "Um, I I think so."
        #expect(TextPipeline.prepare(input, options: PipelineOptions(removeFillers: false)) == input)
    }

    @Test("Stutters and restarts", arguments: [
        ("I I think so.", "I think so."),
        ("I, I think so.", "I think so."),
        ("The the cat sat.", "The cat sat."),
        ("Go to the the the shop.", "Go to the shop."),
        ("We're we're late.", "We're late."),
        ("W- what time is it?", "What time is it?"),
        ("See you to- tomorrow.", "See you tomorrow."),
        ("I- I agree.", "I agree."),
    ])
    func stutters(input: String, expected: String) {
        #expect(TextPipeline.prepare(input) == expected)
    }

    @Test("Intended repetition survives", arguments: [
        "I know that that is true.",
        "She had had enough.",
        "Did I tell you you were right?",
        "When I found it it was broken.",
        "Turn it on on Monday.",
        "It was so so good.",
        "Pre- and post-war Europe.",
        "Re-read the e-mail.",
    ])
    func intendedRepetition(input: String) {
        #expect(TextPipeline.prepare(input) == input)
    }

    @Test("Spoken commands", arguments: [
        ("Hello. New paragraph. Thanks.", "Hello.\n\nThanks."),
        ("Hello new line thanks", "Hello\nThanks"),
        ("Buy milk, new line, buy eggs.", "Buy milk\nBuy eggs."),
        ("Dear Sam: new line thanks for coming.", "Dear Sam:\nThanks for coming."),
        ("First item New Line second item", "First item\nSecond item"),
        ("Notes new-paragraph done", "Notes\n\nDone"),
        ("Sign off. New line.", "Sign off."),
    ])
    func spokenCommands(input: String, expected: String) {
        #expect(TextPipeline.prepare(input) == expected)
    }

    @Test("'New line' as an ordinary phrase is left alone", arguments: [
        "We need a new line of products.",
        "The new line looks great.",
        "They launched a brand new paragraph style.",
        "Stand in the new lines.",
    ])
    func commandLookalikes(input: String) {
        #expect(TextPipeline.prepare(input) == input)
    }

    @Test("Spoken commands can be turned off")
    func commandsOff() {
        #expect(TextPipeline.prepare("Hello new line thanks", options: PipelineOptions(spokenCommands: false))
            == "Hello new line thanks")
    }

    @Test("Whitespace and punctuation", arguments: [
        ("  Hello   there ,  friend .  ", "Hello there, friend."),
        ("Wait , what ?", "Wait, what?"),
        ("Hello\t\tworld", "Hello world"),
        ("Line one \n  line two", "Line one\nline two"),
        ("A\n\n\n\nB", "A\n\nB"),
        ("For example, e.g., this.", "For example, e.g., this."),
        ("", ""),
        ("   ", ""),
    ])
    func whitespace(input: String, expected: String) {
        #expect(TextPipeline.prepare(input) == expected)
    }

    @Test("Brand casing is never forced at a sentence start")
    func brandCasing() {
        #expect(TextPipeline.prepare("Um, iPhone sales are up.") == "iPhone sales are up.")
    }
}

@Suite("TextPipeline.finalize")
struct FinalizeTests {
    let noDictionary = DictionaryCorrector(entries: [])

    func finalize(_ text: String, _ style: WritingStyle, snippets: [Snippet] = [], vocabulary: [String] = [],
                  dictionary: [DictionaryEntry] = []) -> PipelineResult {
        TextPipeline.finalize(text, style: style, corrector: DictionaryCorrector(entries: dictionary),
                              snippets: snippets, vocabulary: vocabulary)
    }

    // MARK: Styles

    @Test("Formal", arguments: [
        ("see you tomorrow", "See you tomorrow."),
        ("see you tomorrow. bring the slides", "See you tomorrow. Bring the slides."),
        ("is that right?", "Is that right?"),
        ("that's great!", "That's great!"),
        ("we left at 9 a.m. then drove", "We left at 9 a.m. then drove."),
        ("wait... maybe not", "Wait... maybe not."),
        ("finish the list,", "Finish the list."),
        ("milk\neggs", "Milk\nEggs."),
        ("shopping:\n1. Milk\n2. Eggs", "Shopping:\n1. Milk\n2. Eggs"),
        ("he said \"hi.\"", "He said \"hi.\""),
        ("iPhone sales are up", "iPhone sales are up."),
        ("the total is 42", "The total is 42."),
    ])
    func formal(input: String, expected: String) {
        #expect(finalize(input, .formal).text == expected)
    }

    @Test("Casual", arguments: [
        ("Sounds good.", "Sounds good"),
        ("sounds good.", "Sounds good"),
        ("Are you coming?", "Are you coming?"),
        ("That's amazing!", "That's amazing!"),
        ("Sounds good. See you then.", "Sounds good. See you then."),
        ("Meet me at 9 a.m.", "Meet me at 9 a.m."),
        ("Wait for it...", "Wait for it..."),
        ("Line one.\nLine two.", "Line one.\nLine two."),
        ("I think we should probably move the meeting to next week because half the team is out.",
         "I think we should probably move the meeting to next week because half the team is out."),
    ])
    func casual(input: String, expected: String) {
        #expect(finalize(input, .casual).text == expected)
    }

    @Test("Very casual", arguments: [
        ("Sounds good. See you at the Office.", "sounds good. see you at the office"),
        ("I think NASA and the FBI agree.", "i think NASA and the FBI agree"),
        ("Ship the APIs on Monday.", "ship the APIs on monday"),
        ("Meet at 3PM in Room 4B.", "meet at 3PM in room 4B"),
        ("Email Jo@Example.com or ping @SamLee.", "email Jo@Example.com or ping @SamLee"),
        ("Read https://Example.com/Docs now.", "read https://Example.com/Docs now"),
        ("My iPhone and MacBook died.", "my iPhone and MacBook died"),
        ("Are you there?", "are you there?"),
        ("Yes!", "yes!"),
        ("Hello\nWorld.", "hello\nworld"),
    ])
    func veryCasual(input: String, expected: String) {
        #expect(finalize(input, .veryCasual).text == expected)
    }

    @Test("Very casual keeps vocabulary terms spelled exactly")
    func veryCasualVocabulary() {
        let result = finalize("Ask Claude Code about Anthropic, then anthropic again.", .veryCasual,
                              vocabulary: ["Claude Code", "Anthropic", "lowercase-term"])
        #expect(result.text == "ask Claude Code about Anthropic, then Anthropic again")
    }

    @Test("Excited", arguments: [
        ("That's great.", "That's great!"),
        ("we did it", "We did it!"),
        ("Did we win?", "Did we win?"),
        ("Yes!", "Yes!"),
        ("Wow!!", "Wow!!"),
        ("See you at 9 a.m.", "See you at 9 a.m."),
        ("Well...", "Well..."),
        ("Great news. We shipped.", "Great news. We shipped!"),
    ])
    func excited(input: String, expected: String) {
        #expect(finalize(input, .excited).text == expected)
    }

    // MARK: Snippets

    let calendly = Snippet(trigger: "my calendly link", expansion: "https://calendly.com/levi/30min")
    let signature = Snippet(trigger: "my sign off", expansion: "Best,\nLevi")
    let address = Snippet(trigger: "office address", expansion: "1 Main St, Portland OR")

    @Test("A sentence ending in a link loses the engine's period")
    func snippetDropsPeriodAfterURL() {
        let result = finalize("Here's my calendly link.", .formal, snippets: [calendly])
        #expect(result.text == "Here's https://calendly.com/levi/30min")
        #expect(result.snippets == ["my calendly link"])
    }

    @Test("The whole utterance being a trigger yields exactly the expansion", arguments: WritingStyle.allCases)
    func snippetAlone(style: WritingStyle) {
        #expect(finalize("My calendly link.", style, snippets: [calendly]).text == "https://calendly.com/levi/30min")
        #expect(finalize("my sign-off", style, snippets: [signature]).text == "Best,\nLevi")
    }

    @Test("Triggers match case- and punctuation-insensitively")
    func snippetTolerance() {
        let result = finalize("Thanks for today, my Sign-off", .formal, snippets: [signature])
        #expect(result.text == "Thanks for today, Best,\nLevi")
    }

    @Test("Expansions survive every style untouched", arguments: WritingStyle.allCases)
    func snippetSurvivesStyle(style: WritingStyle) {
        let result = finalize("Send it to the office address please", style, snippets: [address])
        #expect(result.text.contains("1 Main St, Portland OR"))
    }

    @Test("Expansions are protected from dictionary corrections")
    func snippetSurvivesDictionary() {
        let link = Snippet(trigger: "status page", expansion: "https://cloud.example.com")
        let result = finalize("Check the status page and the cloud", .casual, snippets: [link],
                              dictionary: [.correction(hear: "cloud", write: "Claude")])
        #expect(result.text == "Check the https://cloud.example.com and the Claude")
    }

    @Test("Longest trigger wins, disabled snippets never fire, words inside words don't match")
    func snippetPrecedence() {
        let short = Snippet(trigger: "my email", expansion: "me@home.com")
        let long = Snippet(trigger: "my work email", expansion: "me@work.com")
        let off = Snippet(trigger: "the plan", expansion: "SECRET", isEnabled: false)
        let result = finalize("Use my work email, not my email, for the plan.", .formal, snippets: [short, long, off])
        #expect(result.text == "Use me@work.com, not me@home.com, for the plan.")
        #expect(result.snippets == ["my work email", "my email"])
        #expect(finalize("Remy emailed.", .formal, snippets: [short]).text == "Remy emailed.")
    }

    // MARK: Dictionary

    @Test("Dictionary corrections run last and are reported")
    func dictionaryLast() {
        let result = finalize("ask cloud code to fix it.", .veryCasual,
                              dictionary: [.correction(hear: "cloud code", write: "Claude Code")])
        #expect(result.text == "ask Claude Code to fix it")
        #expect(result.corrections.count == 1)
        #expect(result.corrections.first?.to == "Claude Code")
    }

    @Test("Newlines survive styles", arguments: WritingStyle.allCases)
    func newlinesSurvive(style: WritingStyle) {
        #expect(finalize("first line\n\nsecond line", style).text.contains("\n\n"))
    }

    @Test("Empty input stays empty")
    func empty() {
        #expect(finalize("   ", .formal) == PipelineResult(text: ""))
    }
}
