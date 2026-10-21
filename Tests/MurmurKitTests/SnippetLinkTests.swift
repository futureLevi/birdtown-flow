import Foundation
import MurmurDictionary
import Testing
@testable import MurmurKit

@Suite("Linked snippets")
struct SnippetLinkTests {
    let calendar = Snippet(
        trigger: "my calendar link", expansion: "my calendar", link: "https://calendar.app.google/abc123")

    func finalize(_ text: String, _ style: WritingStyle = .formal, snippets: [Snippet]) -> PipelineResult {
        TextPipeline.finalize(text, style: style, corrector: DictionaryCorrector(entries: []), snippets: snippets)
    }

    @Test("A linked snippet types its plain form and reports the link")
    func expandsToPlainForm() {
        let result = finalize("Book a time on my calendar link.", snippets: [calendar])
        #expect(result.text == "Book a time on my calendar (https://calendar.app.google/abc123).")
        #expect(result.snippets == ["my calendar link"])
        #expect(result.links == [SnippetLink(text: "my calendar", url: "https://calendar.app.google/abc123")])
    }

    @Test("Alone, a linked snippet is exactly its plain form", arguments: WritingStyle.allCases)
    func alone(style: WritingStyle) {
        let result = finalize("My calendar link.", style, snippets: [calendar])
        #expect(result.text == "my calendar (https://calendar.app.google/abc123)")
        #expect(result.links.count == 1)
    }

    // MARK: Part of the expansion

    let booking = Snippet(
        trigger: "my booking line", expansion: "grab a time on my calendar",
        link: "https://calendar.app.google/abc123", linkText: "my calendar")

    @Test("Only the chosen words become the link")
    func partialLink() {
        let result = finalize("Sure, my booking line.", snippets: [booking])
        #expect(result.text == "Sure, grab a time on my calendar (https://calendar.app.google/abc123).")
        #expect(result.links == [SnippetLink(text: "my calendar", url: "https://calendar.app.google/abc123")])
        #expect(LinkedText.runs(in: result.text, links: result.links) == [
            .init("Sure, grab a time on "),
            .init("my calendar", url: "https://calendar.app.google/abc123"),
            .init("."),
        ])
    }

    @Test("The address goes right after the linked words, wherever they are")
    func partialLinkInTheMiddle() {
        var snippet = booking
        snippet.expansion = "Here's my calendar, grab any free slot"
        #expect(snippet.typed == "Here's my calendar (https://calendar.app.google/abc123), grab any free slot")
        let result = finalize("My booking line.", snippets: [snippet])
        #expect(result.text == snippet.typed)
        #expect(LinkedText.runs(in: result.text, links: result.links) == [
            .init("Here's "),
            .init("my calendar", url: "https://calendar.app.google/abc123"),
            .init(", grab any free slot"),
        ])
    }

    @Test("The words match ignoring case and spaces, keep the expansion's spelling, and link once")
    func partialLinkMatching() {
        var snippet = booking
        snippet.expansion = "Grab a time on My Calendar, or ask me for my calendar"
        snippet.linkText = "  MY CALENDAR "
        #expect(snippet.linked == SnippetLink(text: "My Calendar", url: "https://calendar.app.google/abc123"))
        #expect(snippet.typed
            == "Grab a time on My Calendar (https://calendar.app.google/abc123), or ask me for my calendar")
    }

    @Test("Words that aren't in the expansion, or none, link all of it", arguments: [nil, "", "  ", "my diary"])
    func partialLinkFallsBack(words: String?) {
        var snippet = booking
        snippet.linkText = words
        #expect(snippet.linked
            == SnippetLink(text: "grab a time on my calendar", url: "https://calendar.app.google/abc123"))
        #expect(snippet.typed == "grab a time on my calendar (https://calendar.app.google/abc123)")
    }

    @Test("Words to link without an address type the expansion as is")
    func partialLinkNeedsAnAddress() {
        var snippet = booking
        snippet.link = nil
        #expect(snippet.linked == nil)
        #expect(snippet.linkedRange == nil)
        #expect(snippet.typed == "grab a time on my calendar")
        #expect(finalize("my booking line", snippets: [snippet]).links.isEmpty)
    }

    @Test("Snippets without a link report none")
    func unlinked() {
        let plain = Snippet(trigger: "my calendly link", expansion: "https://calendly.com/levi")
        let blank = Snippet(trigger: "my zoom", expansion: "Zoom", link: "")
        #expect(finalize("Here's my calendly link and my zoom", snippets: [plain, blank]).links.isEmpty)
        #expect(blank.linked == nil)
    }

    @Test("Snippets saved before links existed still load")
    func decodesOldSnippets() throws {
        let json = """
            [{"id":"6F0C1C1E-6D4B-4B53-9C59-1E0C3D7B1A11","trigger":"my address","expansion":"1 Main St",\
            "isEnabled":true,"createdAt":"2026-10-01T10:00:00Z"}]
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snippets = try decoder.decode([Snippet].self, from: Data(json.utf8))
        #expect(snippets.first?.link == nil)
        #expect(snippets.first?.linkText == nil)
        #expect(snippets.first?.expansion == "1 Main St")
    }

    @Test("History keeps a dictation's links")
    func historyRoundTrip() throws {
        let link = SnippetLink(text: "my calendar", url: "https://calendar.app.google/abc123")
        let record = HistoryRecord(finalText: "See \(link.plain)", links: [link])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HistoryRecord.self, from: encoder.encode(record))
        #expect(decoded.links == [link])
        #expect(try decoder.decode(HistoryRecord.self, from: encoder.encode(HistoryRecord(finalText: "x"))).links == nil)
    }

    // MARK: Addresses

    @Test("Typed links become addresses", arguments: [
        ("https://calendar.app.google/abc123", "https://calendar.app.google/abc123"),
        ("  calendly.com/levi/30min ", "https://calendly.com/levi/30min"),
        ("www.example.com", "https://www.example.com"),
        ("levi@example.com", "mailto:levi@example.com"),
        ("mailto:levi@example.com", "mailto:levi@example.com"),
        ("zoommtg://zoom.us/join?confno=1", "zoommtg://zoom.us/join?confno=1"),
    ])
    func normalizes(raw: String, expected: String) {
        #expect(SnippetLink.normalizedURL(raw) == expected)
    }

    @Test("Things that aren't addresses are refused", arguments: [
        "", "   ", "my calendar", "calendar", "https://", "://example.com", "@levi", "levi@",
        "https://example.com/a b",
    ])
    func refuses(raw: String) {
        #expect(SnippetLink.normalizedURL(raw) == nil)
    }

    // MARK: Rich text

    let link = SnippetLink(text: "my calendar", url: "https://calendar.app.google/abc123")

    @Test("Runs swap each plain form back for its linked text")
    func runs() {
        let text = " Book a time on \(link.plain), or on \(link.plain)."
        #expect(LinkedText.runs(in: text, links: [link]) == [
            .init(" Book a time on "),
            .init("my calendar", url: link.url),
            .init(", or on "),
            .init("my calendar", url: link.url),
            .init("."),
        ])
    }

    @Test("The same words without the address stay plain")
    func runsNeedTheAddress() {
        let text = "Check my calendar first, then \(link.plain)"
        let runs = LinkedText.runs(in: text, links: [link])
        #expect(runs == [.init("Check my calendar first, then "), .init("my calendar", url: link.url)])
    }

    @Test("Several links, and none")
    func runsSeveral() {
        let zoom = SnippetLink(text: "our Zoom", url: "https://zoom.us/j/1")
        let text = "\(zoom.plain) and \(link.plain)"
        #expect(LinkedText.runs(in: text, links: [link, zoom]) == [
            .init("our Zoom", url: zoom.url), .init(" and "), .init("my calendar", url: link.url),
        ])
        #expect(LinkedText.runs(in: "Hello", links: []) == [.init("Hello")])
        #expect(!LinkedText.hasLinks(LinkedText.runs(in: "Hello", links: [link])))
    }

    @Test("HTML is escaped and keeps line breaks")
    func html() {
        let odd = SnippetLink(text: "Q&A <notes>", url: "https://example.com/?a=1&b=\"2\"")
        let runs = LinkedText.runs(in: "Hi\n\(odd.plain)", links: [odd])
        #expect(LinkedText.html(runs) == "<meta charset=\"utf-8\">Hi<br>"
            + "<a href=\"https://example.com/?a=1&amp;b=&quot;2&quot;\">Q&amp;A &lt;notes&gt;</a>")
    }
}
