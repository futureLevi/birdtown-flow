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
    ///
    /// One pass, counting each record's words once: Home calls this over the whole history,
    /// which is kept forever by default.
    public static func compute(
        from records: [HistoryRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DictationStats {
        // Half-open: a record at the instant next week starts belongs to next week.
        let week = calendar.dateInterval(of: .weekOfYear, for: now)

        var dictationCount = 0
        var totalWords = 0
        var wordsThisWeek = 0
        var spokenSeconds = 0.0
        var measuredWords = 0
        var measuredSeconds = 0.0
        var days = Set<Date>()

        for record in records {
            guard record.outcome == .inserted || record.outcome == .copied, record.hasText else { continue }
            let words = record.wordCount
            dictationCount += 1
            totalWords += words
            spokenSeconds += record.audioDuration
            if let week, record.createdAt >= week.start && record.createdAt < week.end {
                wordsThisWeek += words
            }
            // Exactly the records `wordsPerMinute` can measure.
            if record.audioDuration >= 2 && words > 0 {
                measuredWords += words
                measuredSeconds += record.audioDuration
            }
            days.insert(calendar.startOfDay(for: record.createdAt))
        }
        guard dictationCount > 0 else { return DictationStats() }

        // Weighted by audio duration: total measured words over total measured minutes, so a
        // two-second "yes" can't swing the average as much as a two-minute email.
        let measuredMinutes = measuredSeconds / 60
        let averageWPM = measuredMinutes > 0 ? Int((Double(measuredWords) / measuredMinutes).rounded()) : 0

        // Typing time saved, less the time spent speaking; never negative.
        let spokenMinutes = spokenSeconds / 60
        let typingMinutes = Double(totalWords) / Double(typingWPM)
        let minutesSaved = Int(max(0, typingMinutes - spokenMinutes).rounded(.down))

        return DictationStats(
            totalWords: totalWords,
            wordsThisWeek: wordsThisWeek,
            averageWPM: averageWPM,
            dayStreak: streak(days: days, now: now, calendar: calendar),
            minutesSaved: minutesSaved,
            dictationCount: dictationCount
        )
    }

    /// Consecutive days with a dictation, counting back from today — or from yesterday when
    /// today has none yet, so the streak doesn't read zero every morning.
    static func streak(of records: [HistoryRecord], now: Date, calendar: Calendar) -> Int {
        streak(days: Set(records.map { calendar.startOfDay(for: $0.createdAt) }), now: now, calendar: calendar)
    }

    /// `streak(of:now:calendar:)` over days already reduced to their start.
    static func streak(days: Set<Date>, now: Date, calendar: Calendar) -> Int {
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
