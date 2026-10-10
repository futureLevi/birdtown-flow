import Foundation
import Testing
@testable import MurmurKit

@Suite("TimingRollup")
struct TimingRollupTests {
    private func record(
        total: Int, transcribe: Int = 0, polish: Int = 0, outcome: DictationOutcome = .inserted
    ) -> HistoryRecord {
        HistoryRecord(
            finalText: "Hello.",
            timings: DictationTimings(transcribeMs: transcribe, polishMs: polish, totalMs: total),
            outcome: outcome)
    }

    @Test("Nearest rank: always one of the values")
    func percentiles() {
        let ten = Array(1...10).map { $0 * 100 }
        #expect(TimingRollup.percentile(50, of: ten) == 500)
        #expect(TimingRollup.percentile(90, of: ten) == 900)
        #expect(TimingRollup.percentile(50, of: [700]) == 700)
        #expect(TimingRollup.percentile(90, of: [700]) == 700)
        // Two values: the median is the faster one, p90 the slower.
        #expect(TimingRollup.percentile(50, of: [300, 900]) == 300)
        #expect(TimingRollup.percentile(90, of: [300, 900]) == 900)
        #expect(TimingRollup.percentile(100, of: ten) == 1_000)
    }

    @Test("Nothing to roll up without a dictation that was typed or copied")
    func nothing() {
        #expect(TimingRollup.recent([HistoryRecord]()) == nil)
        #expect(TimingRollup.recent([
            record(total: 900, outcome: .failed),
            record(total: 0),
            record(total: 400, outcome: .cancelled),
        ]) == nil)
    }

    @Test("Failed, cancelled, empty and unmeasured dictations are skipped")
    func skips() throws {
        let rollup = try #require(TimingRollup.recent([
            record(total: 1_000, transcribe: 300),
            record(total: 9_000, transcribe: 8_000, outcome: .failed),
            record(total: 200, transcribe: 150, outcome: .empty),
            record(total: 0),
            record(total: 5_000, transcribe: 4_000, outcome: .cancelled),
            record(total: 2_000, transcribe: 500, outcome: .copied),
        ]))
        #expect(rollup.count == 2)
        #expect(rollup.total == TimingRollup.Spread(p50: 1_000, p90: 2_000))
        #expect(rollup.transcribe == TimingRollup.Spread(p50: 300, p90: 500))
        #expect(rollup.polish == nil)
    }

    @Test("Only the most recent ones count, newest first")
    func limit() throws {
        let newer = (0..<3).map { _ in record(total: 1_000) }
        let older = (0..<5).map { _ in record(total: 9_000) }
        let rollup = try #require(TimingRollup.recent(newer + older, limit: 3))
        #expect(rollup.count == 3)
        #expect(rollup.total == TimingRollup.Spread(p50: 1_000, p90: 1_000))
    }

    @Test("Polish counts only the dictations it ran on")
    func polishOnlyWhereItRan() throws {
        var records = (1...10).map { record(total: $0 * 100, transcribe: 50) }
        records.append(record(total: 4_000, transcribe: 50, polish: 3_600))
        records.append(record(total: 1_500, transcribe: 50, polish: 1_200))
        let rollup = try #require(TimingRollup.recent(records))
        #expect(rollup.count == 12)
        #expect(rollup.polish == TimingRollup.Spread(p50: 1_200, p90: 3_600))
        #expect(rollup.transcribe == TimingRollup.Spread(p50: 50, p90: 50))
    }

    @Test("The summary names the count, then total, transcribe and polish")
    func summary() {
        let format: (Int) -> String = { $0 < 1_000 ? "\($0) ms" : "\(Double($0) / 1_000) s" }
        let full = TimingRollup(
            count: 50, total: TimingRollup.Spread(p50: 1_900, p90: 4_200),
            transcribe: TimingRollup.Spread(p50: 310, p90: 640), polish: TimingRollup.Spread(p50: 1_200, p90: 3_100))
        #expect(full.summary(format: format)
            == "Last 50: total p50 1.9 s, p90 4.2 s · transcribe p50 310 ms, p90 640 ms · polish p50 1.2 s, p90 3.1 s")
        let unpolished = TimingRollup(count: 3, total: TimingRollup.Spread(p50: 400, p90: 600))
        #expect(unpolished.summary(format: format) == "Last 3: total p50 400 ms, p90 600 ms")
    }
}
