import Foundation

/// How fast recent dictations were, typically (p50) and on a slow day (p90), for the line at
/// the top of History's Timings view:
/// "Last 50: total p50 1.9 s, p90 4.2 s · transcribe p50 310 ms, p90 640 ms · polish p50 1.2 s, p90 3.1 s".
public struct TimingRollup: Sendable, Equatable {
    /// One stage's median and 90th percentile, in milliseconds.
    public struct Spread: Sendable, Equatable {
        public var p50: Int
        public var p90: Int

        public init(p50: Int, p90: Int) {
            self.p50 = p50
            self.p90 = p90
        }
    }

    /// How many dictations it covers.
    public var count: Int
    public var total: Spread
    /// Over the dictations that ran the stage; `nil` when none did (polish off, say).
    public var transcribe: Spread?
    public var polish: Spread?

    public init(count: Int, total: Spread, transcribe: Spread? = nil, polish: Spread? = nil) {
        self.count = count
        self.total = total
        self.transcribe = transcribe
        self.polish = polish
    }

    /// How many recent dictations History rolls up.
    public static let defaultLimit = 50

    /// Over the `limit` most recent of `records` (newest first, as History keeps them) that
    /// were typed or copied and have timings. Failed, cancelled and empty ones say nothing
    /// about how fast a dictation is, so they're skipped. A stage counts only the dictations
    /// that ran it: polish's numbers are for polished dictations, including ones whose
    /// rewrite wasn't used, since the time was still spent. `nil` when none qualify.
    public static func recent(
        _ records: some Sequence<HistoryRecord>, limit: Int = TimingRollup.defaultLimit
    ) -> TimingRollup? {
        var totals: [Int] = []
        var transcribes: [Int] = []
        var polishes: [Int] = []
        for record in records {
            guard totals.count < limit else { break }
            guard record.outcome == .inserted || record.outcome == .copied, record.timings.totalMs > 0
            else { continue }
            totals.append(record.timings.totalMs)
            if record.timings.transcribeMs > 0 { transcribes.append(record.timings.transcribeMs) }
            if record.timings.polishMs > 0 { polishes.append(record.timings.polishMs) }
        }
        guard let total = spread(totals) else { return nil }
        return TimingRollup(count: totals.count, total: total, transcribe: spread(transcribes), polish: spread(polishes))
    }

    /// The line itself, each time in `format` ("1.9 s", "310 ms").
    public func summary(format: (Int) -> String) -> String {
        var stages = [Self.describe("total", total, format: format)]
        if let transcribe { stages.append(Self.describe("transcribe", transcribe, format: format)) }
        if let polish { stages.append(Self.describe("polish", polish, format: format)) }
        return "Last \(count): " + stages.joined(separator: " · ")
    }

    /// "polish p50 1.2 s, p90 3.1 s".
    private static func describe(_ name: String, _ spread: Spread, format: (Int) -> String) -> String {
        "\(name) p50 \(format(spread.p50)), p90 \(format(spread.p90))"
    }

    /// The median and 90th percentile of `values`, or `nil` when there are none.
    static func spread(_ values: [Int]) -> Spread? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return Spread(p50: percentile(50, of: sorted), p90: percentile(90, of: sorted))
    }

    /// The nearest-rank percentile of `sorted` (ascending, not empty): the smallest value with
    /// at least `percent`% of the values at or below it. Always one of the values, never an
    /// average of two, so a p50 over two dictations is the faster one.
    static func percentile(_ percent: Int, of sorted: [Int]) -> Int {
        let rank = (percent * sorted.count + 99) / 100
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
