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

/// Two windows either side of a cut at `cut` seconds, kept and joined as
/// `SegmentedTranscriber` does: what the second one keeps, and the joined text.
private func stitchedAcrossCut(
    _ before: [(String, Double)], _ after: [(String, Double)], cut: Double
) -> (kept: SegmentStitcher.Kept, text: String) {
    let first = SegmentStitcher.keep(tokens(before), in: 0..<cut, after: nil)
    let second = SegmentStitcher.keep(
        tokens(after), in: cut..<Double.infinity, after: first.lastWords, following: first.nextWord
    )
    let text = SegmentStitcher.join([
        SegmentStitcher.Part(leadingPunctuation: first.leadingPunctuation, text: first.text),
        SegmentStitcher.Part(leadingPunctuation: second.leadingPunctuation, text: second.text),
    ])
    return (second, text)
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
        let first = SegmentStitcher.keep(heard, in: 0..<12, after: nil)
        #expect(first.text == "one twos")
        // The word it leaves to the next window, for that window's seam check.
        #expect(first.nextWord == SegmentStitcher.TimedWord(core: "three", start: 12.0, tokens: 3..<4))
        let tail = SegmentStitcher.keep(heard, in: 12..<Double.infinity, after: nil)
        #expect(tail.text == "three four")
        #expect(tail.nextWord == nil)
    }

    @Test("A word heard past the cut by one window and before it by the next is still written once")
    func seamLoss() {
        // The previous window kept "to" and heard "the" just after the cut, so left it.
        let previous = SegmentStitcher.TimedWord(core: "to", start: 11.6, tokens: 0..<1)
        let following = SegmentStitcher.TimedWord(core: "the", start: 12.04, tokens: 1..<2)
        // This window times "the" a frame earlier, just before the cut. It heard "to" too, so
        // it keeps everything after its own "to".
        let heard = tokens([(" to", 11.62), (" the", 11.97), (" store", 12.3), (".", 12.6)])
        let kept = SegmentStitcher.keep(heard, in: 12..<Double.infinity, after: previous, following: following)
        #expect(kept.text == "the store.")
        #expect(kept.tokens.map(\.index) == [1, 2, 3])
        #expect(kept.leadingPunctuation == "")
        #expect(SegmentStitcher.keep(heard, in: 12..<Double.infinity, after: previous).text == "the store.")
        // …unless the previous window kept "the" already.
        let keptThe = SegmentStitcher.TimedWord(core: "the", start: 11.95, tokens: 1..<2)
        #expect(SegmentStitcher.keep(heard, in: 12..<Double.infinity, after: keptThe, following: following).text
            == "store.")

        // When this window's audio starts after "to", only the word left over can save "the"…
        let late = tokens([(" the", 11.97), (" store", 12.3), (".", 12.6)])
        #expect(SegmentStitcher.keep(late, in: 12..<Double.infinity, after: previous, following: following).text
            == "the store.")
        #expect(SegmentStitcher.keep(late, in: 12..<Double.infinity, after: previous).text == "store.")
        // …and not when it's another word, or too far from the one left over.
        let other = SegmentStitcher.TimedWord(core: "a", start: 12.04, tokens: 1..<2)
        #expect(SegmentStitcher.keep(late, in: 12..<Double.infinity, after: previous, following: other).text == "store.")
        let later = SegmentStitcher.TimedWord(core: "the", start: 12.2, tokens: 1..<2)
        #expect(SegmentStitcher.keep(late, in: 12..<Double.infinity, after: previous, following: later).text == "store.")
    }

    @Test("Words both windows timed past the cut are written once when the last words line up")
    func seamRun() {
        // CI's long recording: the previous window timed "and tell" before a cut at 21.5 s,
        // this one after it, half a second later; "and" alone would never match "tell".
        let tail = [("estimates", 20.1), ("honest", 20.6), ("and", 21.1), ("tell", 21.3)].enumerated().map {
            SegmentStitcher.TimedWord(core: $1.0, start: $1.1, tokens: $0..<($0 + 1))
        }
        let heard = tokens([
            (" estimates", 20.2), (" honest", 20.7), (",", 21.0), (" and", 21.6), (" tell", 21.8),
            (" me", 22.0), (" early", 22.2),
        ])
        let kept = SegmentStitcher.keep(heard, in: 21.5..<Double.infinity, after: tail)
        #expect(kept.text == "me early")
        #expect(kept.leadingPunctuation == "")
        #expect(kept.lastWords.map(\.core) == ["and", "tell", "me", "early"])
        // With only its last word to go on, the seam still writes it twice.
        #expect(SegmentStitcher.keep(heard, in: 21.5..<Double.infinity, after: tail.last).text == "and tell me early")

        // A phrase really said twice across the cut lines up with its first saying.
        let youKnow = [("you", 11.3), ("know", 11.5)].enumerated().map {
            SegmentStitcher.TimedWord(core: $1.0, start: $1.1, tokens: $0..<($0 + 1))
        }
        let twice = tokens([(" you", 11.32), (" know", 11.52), (",", 11.7), (" you", 12.05), (" know", 12.25), (" what", 12.5)])
        let again = SegmentStitcher.keep(twice, in: 12..<Double.infinity, after: youKnow)
        #expect(again.text == "you know what")
        #expect(again.leadingPunctuation == ",")
    }

    @Test("A mark inside a word at the cut is never carried as leading punctuation")
    func interiorPunctuation() {
        // "don't" written by the previous window, heard again here: only "know" is new.
        let tail = [("i", 23.7), ("don't", 23.98)].enumerated().map {
            SegmentStitcher.TimedWord(core: $1.0, start: $1.1, tokens: $0..<($0 + 1))
        }
        let heard = tokens([(" I", 23.72), (" don", 24.02), ("'", 24.08), ("t", 24.12), (" know", 24.32)])
        let deduplicated = SegmentStitcher.keep(heard, in: 24..<Double.infinity, after: tail)
        #expect(deduplicated.text == "know")
        #expect(deduplicated.leadingPunctuation == "")

        // A word that starts before the cut and ends after it, with nothing to line up with.
        for pieces in [
            [(" don", 23.99), ("'", 24.05), ("t", 24.1), (" know", 24.32)],
            [(" 3", 23.9), (".", 24.0), ("5", 24.05), (" percent", 24.3)],
            [(" co", 23.95), ("-", 24.01), ("op", 24.06), (" members", 24.3)],
        ] {
            let kept = SegmentStitcher.keep(tokens(pieces), in: 24..<Double.infinity, after: nil)
            #expect(kept.text == pieces.last!.0.trimmingCharacters(in: .whitespaces))
            #expect(kept.leadingPunctuation == "")
        }
    }

    @Test("A word cut through at the seam is joined without a stray mark")
    func interiorMarksJoined() {
        // "don't" across a cut at 24 s. The window before keeps it: its first piece starts
        // before the cut.
        let before: [(String, Double)] = [(" I", 23.7), (" don", 23.98), ("'", 24.06), ("t", 24.1), (" know", 24.32)]
        // The next one times it just after the cut…
        let deduplicated = stitchedAcrossCut(
            before, [(" I", 23.72), (" don", 24.02), ("'", 24.08), ("t", 24.12), (" know", 24.32)], cut: 24
        )
        #expect(deduplicated.kept.text == "know")
        #expect(deduplicated.text == "I don't know")
        // …or just before it, with its apostrophe after the cut.
        let straddling = stitchedAcrossCut(
            before, [(" I", 23.71), (" don", 23.99), ("'", 24.05), ("t", 24.09), (" know", 24.31)], cut: 24
        )
        #expect(straddling.kept.text == "know")
        #expect(straddling.text == "I don't know")

        let hyphen = stitchedAcrossCut(
            [(" a", 23.6), (" co", 23.97), ("-", 24.03), ("op", 24.07), (" meeting", 24.4)],
            [(" a", 23.62), (" co", 23.99), ("-", 24.04), ("op", 24.08), (" meeting", 24.41)], cut: 24
        )
        #expect(hyphen.text == "a co-op meeting")
        let decimal = stitchedAcrossCut(
            [(" about", 23.5), (" 3", 23.96), (".", 24.02), ("5", 24.06), (" percent", 24.3)],
            [(" about", 23.52), (" 3", 24.03), (".", 24.07), ("5", 24.11), (" percent", 24.33)], cut: 24
        )
        #expect(decimal.text == "about 3.5 percent")
    }

    @Test("A mark closing the word before the cut is carried, and written once")
    func closingMarksJoined() {
        // The window before the cut ended before hearing the comma, or the full stop.
        let comma = stitchedAcrossCut(
            [(" I", 23.7), (" don", 23.98), ("'", 24.06), ("t", 24.1), (" honestly", 24.4)],
            [(" I", 23.72), (" don", 23.99), ("'", 24.05), ("t", 24.09), (",", 24.15), (" honestly", 24.42)], cut: 24
        )
        #expect(comma.kept.leadingPunctuation == ",")
        #expect(comma.text == "I don't, honestly")
        let stop = stitchedAcrossCut(
            [(" on", 23.5), (" Friday", 23.97), (" see", 24.6)],
            [(" on", 23.52), (" Friday", 24.03), (".", 24.3), (" See", 24.62)], cut: 24
        )
        #expect(stop.kept.leadingPunctuation == ".")
        #expect(stop.text == "on Friday. See")

        // A quote opened after the cut is inside the word. The closing one is carried, and
        // added only where the window before didn't write it.
        let quoted: [(String, Double)] = [(" said", 23.92), (" \"", 24.04), ("yes", 24.08), ("\"", 24.32), (" Then", 24.62)]
        let heardBoth = stitchedAcrossCut(
            [(" said", 23.9), (" \"", 24.02), ("yes", 24.06), ("\"", 24.3), (" Then", 24.6)], quoted, cut: 24
        )
        #expect(heardBoth.kept.leadingPunctuation == "\"")
        #expect(heardBoth.text == "said \"yes\" Then")
        let heardOpening = stitchedAcrossCut([(" said", 23.9), (" \"", 24.02), ("yes", 24.06)], quoted, cut: 24)
        #expect(heardOpening.text == "said \"yes\" Then")
        let fullStop = stitchedAcrossCut(
            [(" said", 23.9), (" \"", 24.02), ("yes", 24.06), ("\"", 24.3)],
            [(" said", 23.92), (" \"", 24.04), ("yes", 24.08), ("\"", 24.32), (".", 24.4), (" Then", 24.62)], cut: 24
        )
        #expect(fullStop.kept.leadingPunctuation == "\".")
        #expect(fullStop.text == "said \"yes\". Then")

        // Lined up on words both windows heard well before the cut, the mark after them is
        // carried too, though the window before already wrote it.
        let possessive = stitchedAcrossCut(
            [(" the", 23.2), (" players", 23.5), ("'", 23.8), (" ball", 24.3)],
            [(" the", 23.22), (" players", 23.52), ("'", 23.82), (" ball", 24.32)], cut: 24
        )
        #expect(possessive.kept.leadingPunctuation == "'")
        #expect(possessive.text == "the players' ball")
        let bracket = stitchedAcrossCut(
            [(" see", 23.2), (" (", 23.4), ("above", 23.5), (")", 23.8), (" then", 24.3)],
            [(" see", 23.25), (" (", 23.42), ("above", 23.55), (")", 23.83), (" then", 24.35)], cut: 24
        )
        #expect(bracket.text == "see (above) then")
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

    @Test("The windows joined so far are how the whole transcript begins")
    func joinGrowsAtTheEnd() {
        // What `ProgressivePolisher` splits while recording must be the start of what key-up
        // splits, or no part polished early would match.
        typealias Part = SegmentStitcher.Part
        let parts = [
            Part(text: "on Friday"), Part(leadingPunctuation: ".", text: "See you"), Part(text: ""),
            Part(leadingPunctuation: ",", text: "said \"yes\""), Part(leadingPunctuation: "\".", text: "Then home."),
        ]
        let whole = SegmentStitcher.join(parts)
        #expect(whole == "on Friday. See you, said \"yes\". Then home.")
        for count in 1..<parts.count {
            #expect(whole.hasPrefix(SegmentStitcher.join(Array(parts.prefix(count)))))
        }
    }

    @Test("A word repeated across a seam is reported unless the whole transcript repeats it too")
    func doubledSeams() {
        #expect(SegmentStitcher.doubledSeams(["I went to the", "the store."], reference: "I went to the store.")
            == ["the"])
        #expect(SegmentStitcher.doubledSeams(
            ["keep the estimates honest, and tell", "and tell me early. Please", "please send"],
            reference: "keep the estimates honest, and tell me early. Please send"
        ) == ["and tell", "please"])
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
