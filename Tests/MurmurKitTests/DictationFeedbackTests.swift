import Foundation
import Testing
@testable import MurmurKit

@Suite("DictationFeedback")
struct DictationFeedbackTests {
    func classify(_ duration: Double, peak: Float) -> DictationFeedback.Recording {
        DictationFeedback.classify(duration: duration, peakLevel: peak,
                                   minimumAudio: 0.3, silenceLevel: 0.06, noSpeechNotice: 1.0)
    }

    @Test("Short taps are dropped whatever they heard")
    func shortTaps() {
        #expect(classify(0.1, peak: 0) == .drop)
        #expect(classify(0.29, peak: 0.8) == .drop)
    }

    @Test("A brief silent press is dropped quietly")
    func briefSilence() {
        #expect(classify(0.3, peak: 0.01) == .drop)
        #expect(classify(0.99, peak: 0.059) == .drop)
    }

    @Test("A deliberate silent recording is reported")
    func longSilence() {
        #expect(classify(1.0, peak: 0) == .noSpeech)
        #expect(classify(5, peak: 0.059) == .noSpeech)
    }

    @Test("Anything heard is transcribed")
    func speech() {
        #expect(classify(0.3, peak: 0.06) == .speech)
        #expect(classify(4, peak: 0.4) == .speech)
    }

    @Test("The no-speech message names the microphone")
    func noSpeechMessage() {
        #expect(DictationFeedback.noSpeechMessage(deviceName: "MacBook Pro Microphone")
            == "Didn't hear anything · check MacBook Pro Microphone")
        #expect(DictationFeedback.noSpeechMessage(deviceName: nil)
            == "Didn't hear anything · check your microphone")
        #expect(DictationFeedback.noSpeechMessage(deviceName: "  ")
            == "Didn't hear anything · check your microphone")
    }

    @Test("A long microphone name is truncated")
    func longDeviceName() {
        let name = String(repeating: "A", count: 50)
        let message = DictationFeedback.noSpeechMessage(deviceName: name)
        #expect(message.hasSuffix("…"))
        #expect(message.count == "Didn't hear anything · check ".count + DictationFeedback.deviceNameLimit)
    }

    @Test("No words points at History only while the audio is kept")
    func noWords() {
        #expect(DictationFeedback.noWordsMessage(audioSaved: true) == "Didn't catch any words · it's saved in History")
        #expect(DictationFeedback.noWordsMessage(audioSaved: false) == "Didn't catch any words")
        #expect(DictationFeedback.noWordsMessage(audioSaved: false) == DictationFeedback.noWordsPlain)
        #expect(DictationFeedback.noWordsMessage(audioSaved: true).hasPrefix(DictationFeedback.noWordsPlain))
    }

    @Test("Polish fallbacks become a notice")
    func polishNotice() {
        #expect(DictationFeedback.polishNotice(for: "timed out") == "Inserted without polish · timed out")
        #expect(DictationFeedback.polishNotice(for: "No API key") == "Inserted without polish · no API key")
        #expect(DictationFeedback.polishNotice(for: "Claude Code isn't installed")
            == "Inserted without polish · Claude Code isn't installed")
        #expect(DictationFeedback.polishNotice(for: "Language not supported by Apple Intelligence")
            == "Inserted without polish · language not supported by Apple Intelligence")
        #expect(DictationFeedback.polishNotice(for: "Apple Intelligence failed.")
            == "Inserted without polish · Apple Intelligence failed")
    }

    @Test("No note, or a guard rejection, says nothing")
    func polishSilent() {
        #expect(DictationFeedback.polishNotice(for: nil) == nil)
        #expect(DictationFeedback.polishNotice(for: "  ") == nil)
        #expect(DictationFeedback.polishNotice(for: "Rewrite rejected: it changed what was said") == nil)
    }

    @Test("A dictation polished in parts, some kept as dictated, goes in without a notice")
    func partialPolishSilent() {
        #expect(DictationFeedback.polishNotice(for: "Partly polished · 1 of 4 parts kept as dictated (timed out)") == nil)
        #expect(DictationFeedback.polishNotice(
            for: DictationFeedback.partialPolishNote(keptAsDictated: 2, of: 5, reason: "No API key")) == nil)
    }

    @Test("The partial-polish note counts the parts and gives the first reason's opening clause", arguments: [
        ("Timed out after 4 s", "Partly polished · 1 of 4 parts kept as dictated (timed out after 4 s)"),
        ("Rewrite rejected: it changed what was said", "Partly polished · 1 of 4 parts kept as dictated (rewrite rejected)"),
        ("No API key", "Partly polished · 1 of 4 parts kept as dictated (no API key)"),
        ("Claude Code isn't installed", "Partly polished · 1 of 4 parts kept as dictated (Claude Code isn't installed)"),
        ("Apple Intelligence failed.", "Partly polished · 1 of 4 parts kept as dictated (Apple Intelligence failed)"),
        ("", "Partly polished · 1 of 4 parts kept as dictated"),
    ])
    func partialPolishNote(reason: String, expected: String) {
        let note = DictationFeedback.partialPolishNote(keptAsDictated: 1, of: 4, reason: reason)
        #expect(note == expected)
        // History shows it as is: it has no ":" to be shortened at.
        #expect(!note.contains(":"))
    }
}
