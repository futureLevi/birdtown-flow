import Foundation

/// How long polish may take for a given amount of work.
///
/// The user's setting (`Settings.polishTimeout`) is the limit for a normal dictation. A long
/// one is more work: a single request writes more words, and a text polished in parts
/// (`PolishChunker`) sends them a few at a time, in rounds. Held to the normal limit, a long
/// dictation would time out part-way by design of the limit rather than any fault of the
/// provider, so each round gets the normal limit again, scaled by how much longer than a
/// normal dictation its longest request is. `maximum` keeps a stalled provider from holding
/// any dictation for long.
public enum PolishTimeLimit {
    /// The bounds of the user's setting, and of any limit made from it. Zero or less would
    /// make polish always fail.
    public static let minimum: Double = 0.5
    public static let maximum: Double = 30
    /// A request up to this long is a normal dictation, with the user's limit unchanged:
    /// the size of a part (`PolishChunker.targetWords`).
    public static let normalWords = PolishChunker.targetWords

    /// The user's setting, within `minimum...maximum`.
    public static func base(_ setting: Double) -> Double {
        min(max(setting, minimum), maximum)
    }

    /// One request of `words` words: the user's limit up to `normalWords`, then in
    /// proportion to the words.
    public static func seconds(base setting: Double, words: Int) -> Double {
        seconds(base: setting, partWords: [words], concurrency: 1)
    }

    /// Parts of `partWords` words each, sent `concurrency` at a time under one deadline: a
    /// round per `concurrency` parts, each round as long as one request of the longest part.
    public static func seconds(base setting: Double, partWords: [Int], concurrency: Int) -> Double {
        let normal = Self.base(setting)
        guard let longest = partWords.max() else { return normal }
        let atOnce = max(1, concurrency)
        let rounds = (partWords.count + atOnce - 1) / atOnce
        let perRound = normal * max(1, Double(longest) / Double(normalWords))
        return min(max(normal, Double(rounds) * perRound), maximum)
    }

    /// Words as the limits count them, this one and the output budget
    /// (`PolishPrompt.maxTokens(for:)`): runs of non-whitespace, except that in a script
    /// written without spaces (Chinese, Japanese, Thai…) every character counts as one.
    /// Counted by spaces alone, a long Japanese dictation is a word or two, and would get a
    /// normal dictation's time and too few tokens to finish.
    public static func words(in text: String) -> Int {
        var count = 0
        var inWord = false
        for character in text {
            if character.isWhitespace {
                inWord = false
            } else if let scalar = character.unicodeScalars.first, isWrittenWithoutSpaces(scalar) {
                count += 1
                inWord = false
            } else if !inWord {
                count += 1
                inWord = true
            }
        }
        return count
    }

    /// Thai, Lao, Myanmar, Khmer, and Chinese and Japanese: their punctuation, kana,
    /// ideographs and full-width forms. Korean puts spaces between words, so Hangul isn't here.
    static func isWrittenWithoutSpaces(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0E00...0x0EFF, 0x1000...0x109F, 0x1780...0x17FF: true
        case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x3FFFF: true
        default: false
        }
    }
}
