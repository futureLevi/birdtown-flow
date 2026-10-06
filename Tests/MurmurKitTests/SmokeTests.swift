import Foundation
import Testing
@testable import MurmurKit

@Suite("Smoke")
struct SmokeTests {
    @Test func recordWordCount() {
        let record = HistoryRecord(finalText: "Hello there, Murmur.")
        #expect(record.wordCount == 3)
    }
}
