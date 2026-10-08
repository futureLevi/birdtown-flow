import Foundation
import Testing
@testable import MurmurKit

@Suite("Smoke")
struct SmokeTests {
    @Test func recordWordCount() {
        let record = HistoryRecord(finalText: "Hello there, Murmur.")
        #expect(record.wordCount == 3)
    }

    @Test("Word count and hasText agree with split and trimming")
    func wordCountAndHasTextParity() {
        let samples = [
            "", " ", "\n\t ", "one", "  leading", "trailing  ", "a  b\tc\nd", "line\r\nbreak",
            "café naïve", "emoji 👍🏽 here", "\u{00A0}nbsp\u{2003}em", "e\u{0301} combined",
        ]
        for text in samples {
            let record = HistoryRecord(finalText: text)
            #expect(record.wordCount == text.split { $0.isWhitespace || $0.isNewline }.count, "\(text.debugDescription)")
            #expect(record.hasText == !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(text.debugDescription)")
        }
    }
}
