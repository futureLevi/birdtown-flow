import Foundation
import Testing
@testable import MurmurKit

// MARK: - Synthetic audio

private func samples(_ seconds: Double) -> Int { Int((seconds * 16_000).rounded()) }

/// The same linear congruential generator as `ParakeetEngine.nearSilence`: repeatable noise.
private struct Noise {
    var seed: UInt32

    mutating func next() -> UInt32 {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return seed
    }

    /// Uniform in [-amplitude, amplitude].
    mutating func sample(_ amplitude: Float) -> Float {
        (Float(next() >> 8) / Float(1 << 24) * 2 - 1) * amplitude
    }

    /// Uniform in 0..<bound.
    mutating func below(_ bound: Int) -> Int { Int(next() % UInt32(bound)) }
}

/// A 220 Hz tone over absolute samples `range`: −13.5 dBFS at the default amplitude, a
/// stand-in for speech.
private func tone(_ range: Range<Int>, amplitude: Float = 0.3) -> [Float] {
    range.map { amplitude * Float(sin(2 * Double.pi * 220 * Double($0) / 16_000)) }
}

/// Tone throughout, with `silences` (seconds: start, length) replaced by −65 dBFS noise and
/// `dips` by the tone at half amplitude, quieter but not quiet.
private func testAudio(seconds: Double, silences: [(Double, Double)] = [], dips: [(Double, Double)] = []) -> [Float] {
    var audio = tone(0..<samples(seconds))
    var noise = Noise(seed: 0x9E37_79B9)
    for (start, length) in silences {
        for index in samples(start)..<samples(start + length) { audio[index] = noise.sample(1e-3) }
    }
    for (start, length) in dips {
        let range = samples(start)..<samples(start + length)
        audio.replaceSubrange(range, with: tone(range, amplitude: 0.15))
    }
    return audio
}

/// Bursts of 0.3–2.5 s with gaps of 0.05–0.6 s, like a person talking.
private func speechLike(seconds: Double, seed: UInt32) -> [Float] {
    var noise = Noise(seed: seed)
    let total = samples(seconds)
    var audio: [Float] = []
    audio.reserveCapacity(total)
    while audio.count < total {
        let burst = min(total - audio.count, samples(0.3) + noise.below(samples(2.2)))
        audio += tone(audio.count..<audio.count + burst)
        let gap = min(total - audio.count, samples(0.05) + noise.below(samples(0.55)))
        for _ in 0..<gap { audio.append(noise.sample(1e-3)) }
    }
    return audio
}

// MARK: - WAVQuantization

@Suite("WAVQuantization")
struct WAVQuantizationTests {
    @Test("Round trip is the WAV's own 16-bit conversion, read back", arguments: [-1.2, -0.5, 0, 1e-5, 0.7, 1.3] as [Float])
    func roundTrip(x: Float) {
        let expected = Float(Int16((max(-1, min(1, x)) * 32_767).rounded())) / 32_768
        #expect(WAVQuantization.roundTrip(x) == expected)
        #expect(WAVQuantization.roundTrip([x][...]) == [expected])
    }

    @Test("Out-of-range samples clamp, and a second round trip changes the value")
    func clampAndNotIdempotent() {
        #expect(WAVQuantization.pcm16(1.3) == 32_767)
        #expect(WAVQuantization.pcm16(-1.2) == -32_767)
        let once = WAVQuantization.roundTrip(1)
        #expect(WAVQuantization.roundTrip(once) != once)
    }
}

// MARK: - SegmentPlanner

@Suite("SegmentPlanner")
struct SegmentPlannerTests {
    let planner = SegmentPlanner()

    @Test("A window never exceeds one encoder pass")
    func windowSize() {
        #expect(planner.maximumWindowSamples == 239_360)
        #expect(planner.maximumWindowSamples <= 240_000)
    }

    @Test("The cut goes in the middle of the longest pause")
    func longestPause() throws {
        let audio = testAudio(seconds: 14, silences: [(7.0, 0.2), (9.0, 0.5), (11.0, 0.8)])
        let cut = try #require(planner.nextCut(after: 0, audio: audio[...], offset: 0))
        #expect(abs(cut.sample - samples(11.4)) <= 320)
        #expect(cut.kind == .pause(frames: 40))
    }

    @Test("No cut until the window's whole range has been captured")
    func waitsForAudio() {
        let audio = testAudio(seconds: 30, silences: [(11.0, 0.8), (20.0, 0.8)])
        #expect(planner.nextCut(after: 0, audio: audio[..<207_359], offset: 0) == nil)
        #expect(planner.nextCut(after: 0, audio: audio[..<207_360], offset: 0) != nil)
        let lastCut = 96_000
        #expect(planner.nextCut(after: lastCut, audio: audio[..<(lastCut + 207_359)], offset: 0) == nil)
        #expect(planner.nextCut(after: lastCut, audio: audio[..<(lastCut + 207_360)], offset: 0) != nil)
        // Audio that starts after the left context can't place a cut either.
        #expect(planner.nextCut(after: lastCut, audio: audio[64_320...], offset: 64_320) == nil)
    }

    @Test("With no pause, a dip that isn't quiet still takes a forced cut")
    func forcedAtDip() throws {
        let audio = testAudio(seconds: 14, dips: [(10.4, 0.16)])
        let cut = try #require(planner.nextCut(after: 0, audio: audio[...], offset: 0))
        #expect(cut.kind == .forced)
        #expect((samples(10.4)...samples(10.56)).contains(cut.sample))
    }

    @Test("A pause less than 6 s after the last cut is ignored")
    func earlyPauseIgnored() throws {
        let audio = testAudio(seconds: 14, silences: [(3.0, 1.0)])
        let cut = try #require(planner.nextCut(after: 0, audio: audio[...], offset: 0))
        #expect(cut.kind == .forced)
        #expect((96_000..<192_000).contains(cut.sample))
    }

    @Test("Windows tile the recording, each one pass, from 0 to an open-ended tail")
    func windows() {
        let audio = speechLike(seconds: 75, seed: 5)
        let cuts = planner.plan(audio)
        #expect(cuts.count >= 5)
        var windows: [SegmentWindow] = []
        var lastCut = 0
        for cut in cuts {
            #expect(cut.sample % 320 == 0)
            #expect((lastCut + 96_000..<lastCut + 192_000).contains(cut.sample))
            windows.append(planner.window(from: lastCut, to: cut.sample, total: audio.count))
            lastCut = cut.sample
        }
        windows.append(planner.window(from: lastCut, to: nil, total: audio.count))

        #expect(windows.allSatisfy { $0.audio.count <= 240_000 })
        #expect(windows.first?.audio.lowerBound == 0)
        #expect(windows.first?.keep.lowerBound == 0)
        #expect(windows.last?.keep.upperBound == Double.infinity)
        #expect(windows.last?.audio.upperBound == audio.count)
        for (before, after) in zip(windows, windows.dropFirst()) {
            #expect(before.keep.upperBound == after.keep.lowerBound)
            #expect(after.audio.lowerBound == Int((after.keep.lowerBound * 16_000).rounded()) - 32_000)
            #expect(before.audio.upperBound == Int((before.keep.upperBound * 16_000).rounded()) + 15_360)
        }
    }

    @Test("Cuts made live on a growing recording are the cuts planned from all of it",
          arguments: [5_920, 16_000])
    func liveMatchesOffline(step: Int) {
        let audio = speechLike(seconds: 50, seed: 7)
        let planned = planner.plan(audio)
        #expect(planned.count >= 3)

        var noise = Noise(seed: 3)
        var live: [SegmentPlanner.Cut] = []
        var lastCut = 0
        var captured = 0
        while captured < audio.count {
            captured = min(audio.count, captured + step)
            while true {
                // Copied from anywhere at or before what the next cut depends on.
                let offset = noise.below(planner.analysisStart(after: lastCut) + 1)
                guard let cut = planner.nextCut(after: lastCut, audio: audio[offset..<captured], offset: offset)
                else { break }
                live.append(cut)
                lastCut = cut.sample
            }
        }
        #expect(live == planned)
    }

    @Test("A Retry plans from the WAV exactly what the live recording planned")
    func retryParity() {
        // Off the 16-bit grid, as microphone samples are.
        let raw = speechLike(seconds: 40, seed: 11).enumerated().map { $1 * (1 + Float($0 % 7) * 0.013) }
        let live = WAVQuantization.roundTrip(raw[...])
        // `AudioRecorder.readSamples` on a mono 16-bit file: each channel's sum over the count.
        let read = raw.map { (0 + Float(WAVQuantization.pcm16($0)) / 32_768) / Float(1) }
        #expect(live == read)
        #expect(planner.plan(live) == planner.plan(read))
    }
}

// MARK: - SegmentStitcher

private func tokens(_ pieces: [(String, Double)]) -> [SegmentStitcher.TimedToken] {
    pieces.enumerated().map { SegmentStitcher.TimedToken(text: $1.0, start: $1.1, index: $0) }
}

@Suite("SegmentStitcher")
struct SegmentStitcherTests {
    @Test("Pieces group into words, with joiners and trailing punctuation")
    func words() {
        func cores(_ pieces: [String]) -> [String] {
            SegmentStitcher.words(tokens(pieces.map { ($0, 0.0) })).map(\.core)
        }
        #expect(cores([" we", "'", "ll", " go"]) == ["we'll", "go"])
        #expect(cores([" co", "-", "op"]) == ["co-op"])
        #expect(cores([" Hello", ",", " world", "."]) == ["hello", "world"])
        #expect(cores([" '", "cause", " I"]) == ["cause", "i"])
        // The end of a word the window's audio started in belongs to no word.
        #expect(cores(["ing", ".", " Then"]) == ["then"])

        let grouped = SegmentStitcher.words(tokens([(" Hello", 1.0), (",", 1.2), (" world", 1.5)]))
        #expect(grouped.map(\.tokens) == [0..<2, 2..<3])
        #expect(grouped.map(\.start) == [1.0, 1.5])
    }

    @Test("A word belongs to the window holding the start of its first token")
    func keepBoundary() {
        let heard = tokens([(" one", 9.0), (" two", 11.99), ("s", 12.0), (" three", 12.0), (" four", 13.0)])
        #expect(SegmentStitcher.keep(heard, in: 0..<12, after: nil).text == "one twos")
        #expect(SegmentStitcher.keep(heard, in: 12..<Double.infinity, after: nil).text == "three four")
    }

    @Test("Punctuation heard after the previous window's last word is carried as leading punctuation")
    func leadingPunctuation() {
        let heard = tokens([(" on", 11.4), (" Friday", 11.7), (".", 12.02), (" See", 12.5), (" you", 12.7)])
        let kept = SegmentStitcher.keep(heard, in: 12..<Double.infinity, after: nil)
        #expect(kept.text == "See you")
        #expect(kept.leadingPunctuation == ".")
        #expect(kept.lastWord?.core == "you")
        #expect(kept.tokens.map(\.index) == [3, 4])

        typealias Part = SegmentStitcher.Part
        #expect(SegmentStitcher.join([Part(text: "on Friday"), Part(leadingPunctuation: ".", text: "See you")])
            == "on Friday. See you")
        #expect(SegmentStitcher.join([Part(text: "on Friday."), Part(leadingPunctuation: ".", text: "See you")])
            == "on Friday. See you")
        #expect(SegmentStitcher.join([Part(text: "on Friday,"), Part(leadingPunctuation: ".", text: "see you")])
            == "on Friday, see you")
        // Nothing before it to close: dropped.
        #expect(SegmentStitcher.join([Part(leadingPunctuation: ".", text: "See you")]) == "See you")
    }

    @Test("The same word heard on both sides of a cut is written once; a real repeat stays")
    func seamDuplicates() {
        let previous = SegmentStitcher.TimedWord(core: "that", start: 11.95, tokens: 0..<1)
        let twice = tokens([(" that", 12.05), (",", 12.2), (" works", 12.4)])
        let deduplicated = SegmentStitcher.keep(twice, in: 12..<Double.infinity, after: previous)
        #expect(deduplicated.text == "works")
        #expect(deduplicated.leadingPunctuation == ",")

        let earlier = SegmentStitcher.TimedWord(core: "that", start: 11.7, tokens: 0..<1)
        let repeated = tokens([(" that", 12.1), (" works", 12.4)])
        #expect(SegmentStitcher.keep(repeated, in: 12..<Double.infinity, after: earlier).text == "that works")

        // Case and punctuation don't make it a different word.
        let friday = SegmentStitcher.TimedWord(core: "friday", start: 11.9, tokens: 0..<2)
        let again = tokens([(" Friday", 12.0), (" then", 12.4)])
        #expect(SegmentStitcher.keep(again, in: 12..<Double.infinity, after: friday).text == "then")
    }

    @Test("An empty tail adds nothing")
    func emptyTail() {
        let previous = SegmentStitcher.TimedWord(core: "done", start: 30, tokens: 0..<1)
        let kept = SegmentStitcher.keep([], in: 31..<Double.infinity, after: previous)
        #expect(kept == SegmentStitcher.Kept())
        #expect(SegmentStitcher.join([SegmentStitcher.Part(text: "All done."), SegmentStitcher.Part(text: kept.text)])
            == "All done.")
    }

    @Test("Parts join with single spaces and their own capitalisation")
    func joinKeepsCase() {
        let parts = ["and then", "  we left ", "", "Later, home."].map { SegmentStitcher.Part(text: $0) }
        #expect(SegmentStitcher.join(parts) == "and then we left Later, home.")
    }

    @Test("A word repeated across a seam is reported unless the whole transcript repeats it too")
    func doubledSeams() {
        #expect(SegmentStitcher.doubledSeams(["I went to the", "the store."], reference: "I went to the store.")
            == ["the"])
        #expect(SegmentStitcher.doubledSeams(["I went to the", "the store."], reference: "I went to the, the store.")
            .isEmpty)
        #expect(SegmentStitcher.doubledSeams(["I went", "", "to the store."], reference: "").isEmpty)
    }
}

// MARK: - SegmentLedger

@Suite("SegmentLedger")
struct SegmentLedgerTests {
    let audio = (0..<50_000).map { Float($0 % 977) / 977 }

    @Test("The buffer the windows came from matches")
    func matches() {
        var ledger = SegmentLedger()
        #expect(ledger.committedEnd == 0)
        #expect(ledger.matches(audio))
        ledger.commit(range: 0..<20_000, samples: audio[0..<20_000])
        ledger.commit(range: 15_000..<40_000, samples: audio[15_000..<40_000])
        #expect(ledger.committedEnd == 40_000)
        #expect(ledger.matches(audio))
        #expect(ledger.matches(audio.lazy.map { $0 }))
    }

    @Test("A changed sample, a shorter buffer or a shifted one doesn't")
    func mismatches() {
        var ledger = SegmentLedger()
        ledger.commit(range: 15_000..<40_000, samples: audio[15_000..<40_000])

        var changed = audio
        changed[15_003] += 0.5
        #expect(!ledger.matches(changed))
        changed = audio
        changed[39_999] = -1
        #expect(!ledger.matches(changed))
        #expect(!ledger.matches(Array(audio.prefix(39_999))))
        #expect(!ledger.matches(Array(audio.dropFirst())))
    }
}
