import Foundation
import Testing
@testable import MurmurKit

private func nearly(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < 1e-9
}

@Suite("TranscriptionTimeLimit")
struct TranscriptionTimeLimitTests {
    @Test("Short recordings keep the minute every recording had", arguments: [
        TranscriptionTimeLimit.Engine.parakeet, .appleSpeech,
    ])
    func shortRecordings(engine: TranscriptionTimeLimit.Engine) {
        for seconds in [-1.0, 0, 0.3, 10, 15] {
            #expect(TranscriptionTimeLimit.seconds(audioSeconds: seconds, engine: engine) == 60)
        }
    }

    @Test("Parakeet: past the floor, 10 s, 3.4 s per window, and 0.2 s per second of audio")
    func parakeet() {
        #expect(TranscriptionTimeLimit.seconds(audioSeconds: 60, engine: .parakeet) == 60)
        #expect(nearly(TranscriptionTimeLimit.seconds(audioSeconds: 120, engine: .parakeet), 105.4))
        // 101 windows: one per 6 s, and the tail.
        #expect(nearly(TranscriptionTimeLimit.seconds(audioSeconds: 600, engine: .parakeet), 473.4))
        #expect(nearly(TranscriptionTimeLimit.seconds(audioSeconds: 1800, engine: .parakeet), 1393.4))
    }

    @Test("Parakeet: room for recognition at a quarter of its slowest measured speed, plus boosting's whole budget")
    func parakeetCoversItsWork() {
        for seconds in [1.0, 30, 120, 600, 1800] {
            let recognition = seconds / 10
            let limit = TranscriptionTimeLimit.seconds(audioSeconds: seconds, engine: .parakeet)
            #expect(limit > recognition + TranscriptionTimeLimit.boost(audioSeconds: seconds))
        }
    }

    @Test("Parakeet: room for a Retry's windows, each a 15 s pass boosted on its own, then a whole pass")
    func parakeetCoversWindows() {
        for seconds in [60.0, 300, 600, 1800] {
            // At most one cut every 6 s, plus the tail.
            let windows = (seconds / 6).rounded(.up) + 1
            let segmented = windows * (15.0 / 10 + TranscriptionTimeLimit.boost(audioSeconds: 15))
            // A window that fails late sends the recording through whole as well.
            let whole = seconds / 10 + TranscriptionTimeLimit.boost(audioSeconds: seconds)
            let limit = TranscriptionTimeLimit.seconds(audioSeconds: seconds, engine: .parakeet)
            #expect(limit > segmented + whole)
        }
    }

    @Test("Apple Speech: always past its own limit, so its own error is the one that shows")
    func appleSpeech() {
        #expect(TranscriptionTimeLimit.seconds(audioSeconds: 60, engine: .appleSpeech) == 150)
        for seconds in [0.0, 1, 20, 30, 120, 600] {
            let own = TranscriptionTimeLimit.appleSpeech(audioSeconds: seconds)
            #expect(TranscriptionTimeLimit.seconds(audioSeconds: seconds, engine: .appleSpeech) > own)
        }
    }

    @Test("The engines' own budgets")
    func budgets() {
        #expect(TranscriptionTimeLimit.boost(audioSeconds: 0) == 1)
        #expect(nearly(TranscriptionTimeLimit.boost(audioSeconds: 15), 1.9))
        #expect(TranscriptionTimeLimit.boost(audioSeconds: -5) == 1)
        #expect(TranscriptionTimeLimit.appleSpeech(audioSeconds: 0) == 15)
        #expect(TranscriptionTimeLimit.appleSpeech(audioSeconds: 30) == 75)
    }

    @Test("A longer recording never gets less time", arguments: [
        TranscriptionTimeLimit.Engine.parakeet, .appleSpeech,
    ])
    func monotonic(engine: TranscriptionTimeLimit.Engine) {
        var previous = 0.0
        for seconds in stride(from: 0.0, through: 1800, by: 7.5) {
            let limit = TranscriptionTimeLimit.seconds(audioSeconds: seconds, engine: engine)
            #expect(limit >= previous)
            previous = limit
        }
    }
}

@Suite("PolishTimeLimit")
struct PolishTimeLimitTests {
    @Test("The setting is kept within half a second and 30 s")
    func base() {
        #expect(PolishTimeLimit.base(4) == 4)
        #expect(PolishTimeLimit.base(0) == 0.5)
        #expect(PolishTimeLimit.base(-3) == 0.5)
        #expect(PolishTimeLimit.base(100) == 30)
    }

    @Test("A normal dictation gets the setting, unchanged", arguments: [1.0, 4, 15])
    func normalDictation(setting: Double) {
        for words in [0, 1, 40, PolishTimeLimit.normalWords] {
            #expect(PolishTimeLimit.seconds(base: setting, words: words) == setting)
        }
    }

    @Test("One long request gets the setting per normal dictation's worth of words, up to 30 s")
    func oneLongRequest() {
        #expect(PolishTimeLimit.seconds(base: 4, words: 300) == 8)
        #expect(PolishTimeLimit.seconds(base: 4, words: 600) == 16)
        #expect(PolishTimeLimit.seconds(base: 4, words: 3000) == 30)
        #expect(PolishTimeLimit.seconds(base: 15, words: 450) == 30)
    }

    @Test("Parts get the setting per round, a round being as many parts as go at once")
    func rounds() {
        let nine = Array(repeating: PolishTimeLimit.normalWords, count: 9)
        // 9 parts, 4 at a time (Anthropic): 3 rounds.
        #expect(PolishTimeLimit.seconds(base: 4, partWords: nine, concurrency: 4) == 12)
        #expect(PolishTimeLimit.seconds(base: 4, partWords: nine, concurrency: 3) == 12)
        #expect(PolishTimeLimit.seconds(base: 4, partWords: Array(nine.prefix(4)), concurrency: 4) == 4)
        // One at a time (Apple Intelligence, a local server): held to 30 s.
        #expect(PolishTimeLimit.seconds(base: 4, partWords: nine, concurrency: 1) == 30)
    }

    @Test("A round is as long as its longest part")
    func longestPart() {
        #expect(PolishTimeLimit.seconds(base: 4, partWords: [150, 300, 90], concurrency: 4) == 8)
        #expect(PolishTimeLimit.seconds(base: 4, partWords: [150, 300, 90, 120, 100], concurrency: 4) == 16)
    }

    @Test("Nothing left to polish, or a nonsense concurrency, still gives a sane limit")
    func edges() {
        #expect(PolishTimeLimit.seconds(base: 4, partWords: [], concurrency: 4) == 4)
        #expect(PolishTimeLimit.seconds(base: 4, partWords: [150, 150], concurrency: 0) == 8)
        #expect(PolishTimeLimit.seconds(base: 0, words: 10) == 0.5)
        #expect(PolishTimeLimit.seconds(base: 100, words: 10) == 30)
    }

    @Test("More words never get less time")
    func monotonic() {
        var previous = 0.0
        for words in stride(from: 0, through: 4000, by: 25) {
            let limit = PolishTimeLimit.seconds(base: 4, words: words)
            #expect(limit >= previous)
            previous = limit
        }
    }

    @Test("Words are runs of non-whitespace")
    func words() {
        #expect(PolishTimeLimit.words(in: "") == 0)
        #expect(PolishTimeLimit.words(in: "  So,  we ship\nit.\n\nThen rest ") == 6)
    }

    @Test("In a script written without spaces, every character is a word")
    func unspacedWords() {
        #expect(PolishTimeLimit.words(in: "今日は会議があります。") == 11)
        #expect(PolishTimeLimit.words(in: "我们用Swift写代码") == 7)
        // Korean puts spaces between words.
        #expect(PolishTimeLimit.words(in: "안녕하세요 반갑습니다") == 2)
    }

    @Test("A long dictation without spaces gets a long dictation's time")
    func unspacedDictation() {
        let japanese = String(repeating: "今日は会議があります。", count: 60)
        #expect(PolishTimeLimit.words(in: japanese) == 660)
        #expect(nearly(PolishTimeLimit.seconds(base: 4, words: PolishTimeLimit.words(in: japanese)), 17.6))
    }
}
