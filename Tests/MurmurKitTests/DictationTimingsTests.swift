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

    @Test func noRealtimeFactorWhenTranscribedWhileRecording() throws {
        // Six minutes of speech, but key-up only waited 600 ms for the last window and the
        // tail: 600× would be the engine's speed on those few seconds, not on the recording.
        let live = DictationTimings(transcribeMs: 600, polishMs: 0, totalMs: 1_400, transcribedWhileRecording: true)
        #expect(live.realtimeFactor(audioSeconds: 360) == nil)
        // Everything transcribed after key-up, as for a short dictation or a Retry.
        let afterKeyUp = DictationTimings(transcribeMs: 9_000, polishMs: 0, totalMs: 9_100, transcribedWhileRecording: false)
        let factor = try #require(afterKeyUp.realtimeFactor(audioSeconds: 360))
        #expect(abs(factor - 40) < 0.0001)
    }

    @Test func timingsSavedBeforeTheFlagStillDecode() throws {
        let json = #"{"transcribeMs":9000,"polishMs":7000,"totalMs":17120}"#
        let timings = try JSONDecoder().decode(DictationTimings.self, from: Data(json.utf8))
        #expect(timings == DictationTimings(transcribeMs: 9_000, polishMs: 7_000, totalMs: 17_120))
        #expect(timings.transcribedWhileRecording == nil)
        #expect(timings.realtimeFactor(audioSeconds: 360) != nil)
    }

    @Test func aRecordSavedBeforeTheFlagKeepsItsTimings() throws {
        // The current schema reads it, so the timings aren't lost to the lenient fallback.
        let json = """
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":"2026-09-01T10:00:00Z",\
            "engine":"Parakeet Ultra","rawText":"hello","finalText":"Hello.","corrections":[],"snippets":[],\
            "audioDuration":360,"timings":{"transcribeMs":9000,"polishMs":0,"totalMs":9100},"outcome":"inserted"}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(HistoryRecord.self, from: Data(json.utf8))
        #expect(record.timings == DictationTimings(transcribeMs: 9_000, polishMs: 0, totalMs: 9_100))
    }

    @Test func theFlagIsSavedOnlyWhenSet() throws {
        let live = DictationTimings(transcribeMs: 600, polishMs: 200, totalMs: 900, transcribedWhileRecording: true)
        #expect(try JSONDecoder().decode(DictationTimings.self, from: JSONEncoder().encode(live)) == live)
        let unset = try JSONEncoder().encode(DictationTimings(transcribeMs: 600, polishMs: 200, totalMs: 900))
        #expect(!String(decoding: unset, as: UTF8.self).contains("transcribedWhileRecording"))
    }
}
