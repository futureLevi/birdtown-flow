import Foundation
import Testing
@testable import MurmurKit

@Suite("DictationTimings")
struct DictationTimingsTests {
    @Test func otherIsWhatTranscribeAndPolishLeaveOfTheTotal() {
        let timings = DictationTimings(transcribeMs: 9_500, polishMs: 7_000, totalMs: 17_120)
        #expect(timings.otherMs == 620)
    }

    @Test func otherIsNeverNegative() {
        #expect(DictationTimings(transcribeMs: 900, polishMs: 200, totalMs: 1_000).otherMs == 0)
        #expect(DictationTimings().otherMs == 0)
    }

    @Test func emptyOnlyWhenNothingWasMeasured() {
        #expect(DictationTimings().isEmpty)
        #expect(!DictationTimings(totalMs: 12).isEmpty)
        #expect(!DictationTimings(transcribeMs: 300).isEmpty)
    }

    @Test func realtimeFactor() throws {
        // Six minutes of speech in 9 s is 40× real time.
        let timings = DictationTimings(transcribeMs: 9_000, polishMs: 0, totalMs: 9_100)
        let factor = try #require(timings.realtimeFactor(audioSeconds: 360))
        #expect(abs(factor - 40) < 0.0001)
    }

    @Test func realtimeFactorNeedsBothSides() {
        #expect(DictationTimings(transcribeMs: 0, polishMs: 0, totalMs: 50).realtimeFactor(audioSeconds: 6) == nil)
        #expect(DictationTimings(transcribeMs: 400, polishMs: 0, totalMs: 450).realtimeFactor(audioSeconds: 0) == nil)
    }
}
