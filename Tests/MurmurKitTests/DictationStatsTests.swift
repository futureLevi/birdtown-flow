import Foundation
import Testing
@testable import MurmurKit

@Suite("DictationStats")
struct DictationStatsTests {
    /// A fixed Gregorian calendar so week boundaries don't depend on the machine's locale.
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1  // Sunday
        return calendar
    }()

    /// Wednesday 7 October 2026, 15:00 Pacific.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15))! }

    func daysAgo(_ days: Int, hour: Int = 10) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    func record(_ words: Int, at date: Date, seconds: Double = 0, outcome: DictationOutcome = .inserted) -> HistoryRecord {
        HistoryRecord(createdAt: date, finalText: Array(repeating: "word", count: words).joined(separator: " "),
                      audioDuration: seconds, outcome: outcome)
    }

    @Test("Empty history is all zeros")
    func empty() {
        #expect(DictationStats.compute(from: [], now: now, calendar: calendar) == DictationStats())
    }

    @Test("Only inserted and copied dictations with text count")
    func countsUsefulOnly() {
        let records = [
            record(10, at: daysAgo(0)),
            record(5, at: daysAgo(0), outcome: .copied),
            record(7, at: daysAgo(0), outcome: .failed),
            record(9, at: daysAgo(0), outcome: .cancelled),
            record(0, at: daysAgo(0), outcome: .empty),
        ]
        let stats = DictationStats.compute(from: records, now: now, calendar: calendar)
        #expect(stats.totalWords == 15)
        #expect(stats.dictationCount == 2)
    }

    @Test("Words this week follow the calendar week of now")
    func thisWeek() {
        // Week of Sun 4 Oct – Sat 10 Oct. Three days ago is Sunday (in), four days ago Saturday (out).
        let records = [record(10, at: daysAgo(0)), record(20, at: daysAgo(3, hour: 0)), record(40, at: daysAgo(4, hour: 23))]
        let stats = DictationStats.compute(from: records, now: now, calendar: calendar)
        #expect(stats.wordsThisWeek == 30)
        #expect(stats.totalWords == 70)
    }

    @Test("Streak counts back from today, or from yesterday when today is empty")
    func streak() {
        let today = [record(1, at: daysAgo(0)), record(1, at: daysAgo(1)), record(1, at: daysAgo(2)), record(1, at: daysAgo(4))]
        #expect(DictationStats.compute(from: today, now: now, calendar: calendar).dayStreak == 3)

        let fromYesterday = [record(1, at: daysAgo(1)), record(1, at: daysAgo(2))]
        #expect(DictationStats.compute(from: fromYesterday, now: now, calendar: calendar).dayStreak == 2)

        let lapsed = [record(1, at: daysAgo(2)), record(1, at: daysAgo(3))]
        #expect(DictationStats.compute(from: lapsed, now: now, calendar: calendar).dayStreak == 0)

        let several = [record(1, at: daysAgo(0, hour: 1)), record(1, at: daysAgo(0, hour: 9))]
        #expect(DictationStats.compute(from: several, now: now, calendar: calendar).dayStreak == 1)
    }

    @Test("Streak survives a daylight-saving change")
    func streakAcrossDST() {
        // US DST ended Sunday 1 November 2026; a streak from 30 Oct to 2 Nov spans it.
        let after = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let records = (0..<4).map { offset in
            record(1, at: calendar.date(byAdding: .day, value: -offset, to: after)!)
        }
        #expect(DictationStats.compute(from: records, now: after, calendar: calendar).dayStreak == 4)
    }

    @Test("Average WPM is weighted by audio duration and ignores unmeasurable records")
    func averageWPM() {
        let records = [
            record(100, at: daysAgo(0), seconds: 60),  // 100 wpm over a minute
            record(150, at: daysAgo(0), seconds: 30),  // 300 wpm over half a minute
            record(5, at: daysAgo(0), seconds: 1),  // too short to measure
        ]
        // (100 + 150) words / 1.5 minutes = 166.7
        #expect(DictationStats.compute(from: records, now: now, calendar: calendar).averageWPM == 167)
    }

    @Test("Minutes saved versus typing, floored at zero")
    func minutesSaved() {
        // 900 words take 20 minutes to type at 45 wpm; speaking them took 6 minutes.
        let fast = [record(900, at: daysAgo(0), seconds: 360)]
        #expect(DictationStats.compute(from: fast, now: now, calendar: calendar).minutesSaved == 14)

        // A slow, rambling dictation can't save negative time.
        let slow = [record(10, at: daysAgo(0), seconds: 600)]
        #expect(DictationStats.compute(from: slow, now: now, calendar: calendar).minutesSaved == 0)
    }
}
