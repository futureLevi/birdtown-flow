import Foundation

// CONTRACT — owned by the MurmurKit agent.

/// Headline numbers for the Home screen.
public struct DictationStats: Sendable, Equatable {
    public var totalWords: Int
    public var wordsThisWeek: Int
    /// Average speaking rate across dictations long enough to measure.
    public var averageWPM: Int
    /// Consecutive days, ending today or yesterday, with at least one dictation.
    public var dayStreak: Int
    /// Minutes saved versus typing the same words at `typingWPM`.
    public var minutesSaved: Int
    public var dictationCount: Int

    public static let typingWPM = 45

    public init(
        totalWords: Int = 0,
        wordsThisWeek: Int = 0,
        averageWPM: Int = 0,
        dayStreak: Int = 0,
        minutesSaved: Int = 0,
        dictationCount: Int = 0
    ) {
        self.totalWords = totalWords
        self.wordsThisWeek = wordsThisWeek
        self.averageWPM = averageWPM
        self.dayStreak = dayStreak
        self.minutesSaved = minutesSaved
        self.dictationCount = dictationCount
    }

    public static func compute(
        from records: [HistoryRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DictationStats {
        let useful = records.filter { $0.hasText && ($0.outcome == .inserted || $0.outcome == .copied) }
        let total = useful.reduce(0) { $0 + $1.wordCount }
        return DictationStats(totalWords: total, dictationCount: useful.count)
    }
}
