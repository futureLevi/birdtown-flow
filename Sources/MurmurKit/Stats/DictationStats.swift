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

    /// Only dictations that delivered text (`.inserted` or `.copied`) count toward anything.
    public static func compute(
        from records: [HistoryRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DictationStats {
        let useful = records.filter { $0.hasText && ($0.outcome == .inserted || $0.outcome == .copied) }
        guard !useful.isEmpty else { return DictationStats() }

        let totalWords = useful.reduce(0) { $0 + $1.wordCount }

        var wordsThisWeek = 0
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            // Half-open: a record at the instant next week starts belongs to next week.
            wordsThisWeek = useful
                .filter { $0.createdAt >= week.start && $0.createdAt < week.end }
                .reduce(0) { $0 + $1.wordCount }
        }

        // Weighted by audio duration: total measured words over total measured minutes, so a
        // two-second "yes" can't swing the average as much as a two-minute email.
        let measured = useful.filter { $0.wordsPerMinute != nil }
        let measuredMinutes = measured.reduce(0) { $0 + $1.audioDuration } / 60
        let measuredWords = measured.reduce(0) { $0 + $1.wordCount }
        let averageWPM = measuredMinutes > 0 ? Int((Double(measuredWords) / measuredMinutes).rounded()) : 0

        // Typing time saved, less the time spent speaking; never negative.
        let spokenMinutes = useful.reduce(0) { $0 + $1.audioDuration } / 60
        let typingMinutes = Double(totalWords) / Double(typingWPM)
        let minutesSaved = Int(max(0, typingMinutes - spokenMinutes).rounded(.down))

        return DictationStats(
            totalWords: totalWords,
            wordsThisWeek: wordsThisWeek,
            averageWPM: averageWPM,
            dayStreak: streak(of: useful, now: now, calendar: calendar),
            minutesSaved: minutesSaved,
            dictationCount: useful.count
        )
    }

    /// Consecutive days with a dictation, counting back from today — or from yesterday when
    /// today has none yet, so the streak doesn't read zero every morning.
    static func streak(of records: [HistoryRecord], now: Date, calendar: Calendar) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.createdAt) })
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var day = days.contains(today) ? today : yesterday
        var count = 0
        while days.contains(day) {
            count += 1
            // Stepping by calendar day (not 86,400 s) keeps DST changes from breaking the run.
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = calendar.startOfDay(for: previous)
        }
        return count
    }
}
