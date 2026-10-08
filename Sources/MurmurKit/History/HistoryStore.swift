import Foundation
import MurmurDictionary
import Observation

/// Every dictation, newest first, persisted as JSON with its audio alongside.
///
/// Layout under `directory`:
///
///     history.json          [HistoryRecord], newest first
///     recordings/<id>.wav   16 kHz mono audio for records that still have it
///
/// Audio is written *before* transcription starts (see `DictationController`), so a crash
/// or an engine failure never loses what the user said — the record shows "Retry".
@MainActor
@Observable
public final class HistoryStore {
    public private(set) var records: [HistoryRecord] = []

    public let directory: URL
    public var recordingsDirectory: URL { directory.appendingPathComponent("recordings", isDirectory: true) }
    private var fileURL: URL { directory.appendingPathComponent("history.json") }

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Bumped by every change to `records`, so derived values can be cached until the next one.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var statsCache: (revision: Int, day: Date, calendar: Calendar, stats: DictationStats)?
    @ObservationIgnored private var failedCache: (revision: Int, count: Int)?

    /// Set when `history.json` couldn't be read in full and was copied aside, so the UI can
    /// say so. The copy's name is `history.corrupt-<date>.json`, next to the original.
    public private(set) var quarantinedFile: URL?

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let loaded = Self.load(from: fileURL)
        records = loaded.records
        quarantinedFile = loaded.quarantined
    }

    /// An empty, unsaved store — for previews, snapshots and tests.
    public init(previewRecords: [HistoryRecord]) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-preview-\(UUID().uuidString)")
        records = previewRecords.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Queries

    public func record(id: UUID) -> HistoryRecord? {
        records.first { $0.id == id }
    }

    /// The most recent dictation that produced text — what "Paste last" pastes.
    public var latestWithText: HistoryRecord? {
        records.first { $0.hasText && ($0.outcome == .inserted || $0.outcome == .copied) }
    }

    /// Case- and diacritic-insensitive search over the text, the raw text and the app name.
    public func search(_ query: String) -> [HistoryRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return records }
        return records.filter { record in
            record.finalText.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || record.rawText.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || (record.context?.appName?.range(of: needle, options: [.caseInsensitive]) != nil)
        }
    }

    /// Records grouped by calendar day, newest day first, newest record first within a day.
    public nonisolated static func groupedByDay(
        _ records: [HistoryRecord], calendar: Calendar = .current
    ) -> [(day: Date, records: [HistoryRecord])] {
        let byDay = Dictionary(grouping: records) { calendar.startOfDay(for: $0.createdAt) }
        return byDay.keys.sorted(by: >).map { day in
            (day: day, records: byDay[day, default: []].sorted { $0.createdAt > $1.createdAt })
        }
    }

    /// Instance spelling of `HistoryStore.groupedByDay(_:calendar:)`, for views holding a store.
    public nonisolated func groupedByDay(
        _ records: [HistoryRecord], calendar: Calendar = .current
    ) -> [(day: Date, records: [HistoryRecord])] {
        Self.groupedByDay(records, calendar: calendar)
    }

    /// Where a record's audio lives, if it still exists on disk.
    public func audioURL(for record: HistoryRecord) -> URL? {
        guard let name = record.audioFileName else { return nil }
        let url = recordingsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Where the recorder should write audio for a new record.
    public func newRecordingURL(for id: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(id.uuidString).wav")
    }

    /// Home's headline numbers, recomputed only when `records` or the day changes.
    ///
    /// Views call this from `body`, which re-runs on every records change and on unrelated
    /// invalidations too; computing over the whole history each time was the cost. The week
    /// and the streak depend only on the day of `now`, so a cached value is exact until
    /// midnight or the next mutation.
    public func stats(now: Date = Date(), calendar: Calendar = .current) -> DictationStats {
        // Read through the observed property first, so the calling view still depends on it.
        let records = self.records
        let day = calendar.startOfDay(for: now)
        if let cache = statsCache, cache.revision == revision, cache.day == day, cache.calendar == calendar {
            return cache.stats
        }
        let stats = DictationStats.compute(from: records, now: now, calendar: calendar)
        statsCache = (revision: revision, day: day, calendar: calendar, stats: stats)
        return stats
    }

    /// Dictations that failed and can be retried — the History badge.
    public var failedCount: Int {
        let records = self.records
        if let cache = failedCache, cache.revision == revision { return cache.count }
        let count = records.reduce(0) { $0 + ($1.outcome == .failed ? 1 : 0) }
        failedCache = (revision: revision, count: count)
        return count
    }

    // MARK: - Mutations

    public func add(_ record: HistoryRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        // A new dictation is already the newest, so it only needs sorting into place when it
        // isn't. Ties stay in front, as the stable sort leaves them.
        if records.count > 1, records[1].createdAt > record.createdAt {
            records.sort { $0.createdAt > $1.createdAt }
        }
        revision &+= 1
        scheduleSave()
    }

    public func update(_ record: HistoryRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            add(record)
            return
        }
        records[index] = record
        revision &+= 1
        scheduleSave()
    }

    public func delete(ids: Set<UUID>) {
        for record in records where ids.contains(record.id) {
            removeAudio(of: record)
        }
        records.removeAll { ids.contains($0.id) }
        revision &+= 1
        scheduleSave()
    }

    public func deleteAll() {
        for record in records { removeAudio(of: record) }
        records.removeAll()
        revision &+= 1
        scheduleSave()
    }

    /// Drops text older than `textDays` and audio older than `audioDays`. `nil` keeps forever;
    /// `0` audio days means audio isn't kept past the dictation that produced it.
    public func applyRetention(textDays: Int?, audioDays: Int?, now: Date = Date()) {
        var changed = false
        if let textDays {
            let cutoff = now.addingTimeInterval(-Double(textDays) * 86_400)
            let expired = records.filter { $0.createdAt < cutoff }
            for record in expired { removeAudio(of: record) }
            if !expired.isEmpty {
                records.removeAll { $0.createdAt < cutoff }
                changed = true
            }
        }
        if let audioDays {
            let cutoff = now.addingTimeInterval(-Double(audioDays) * 86_400)
            for index in records.indices where records[index].audioFileName != nil && records[index].createdAt < cutoff {
                // Failed dictations keep their audio — it's the only copy of what was said.
                guard records[index].outcome != .failed else { continue }
                removeAudio(of: records[index])
                records[index].audioFileName = nil
                changed = true
            }
        }
        if changed {
            revision &+= 1
            scheduleSave()
        }
    }

    /// Writes immediately. Call on quit so a debounced save isn't lost.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        Self.write(records, to: fileURL)
    }

    // MARK: - Persistence

    private func removeAudio(of record: HistoryRecord) {
        guard let name = record.audioFileName else { return }
        try? FileManager.default.removeItem(at: recordingsDirectory.appendingPathComponent(name))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = records
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: url)
        }
    }

    nonisolated private static func write(_ records: [HistoryRecord], to url: URL) {
        // No `.sortedKeys`: this runs over the whole history twice per dictation, and the reader
        // doesn't care about key order.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Reads `history.json` without ever losing it.
    ///
    /// Records are decoded one at a time, each first with the current schema and then with a
    /// lenient one that defaults fields older versions didn't write — so one bad record, or an
    /// old file, doesn't cost the rest. If anything still can't be read, the original file is
    /// copied aside before the next save replaces it.
    nonisolated static func load(from url: URL) -> (records: [HistoryRecord], quarantined: URL?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], nil) }
        guard let data = try? Data(contentsOf: url) else {
            // Unreadable (permissions, I/O): keep a copy if possible and start fresh.
            return ([], quarantine(url))
        }
        if data.isEmpty { return ([], nil) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([LossyRecord].self, from: data) else {
            return ([], quarantine(url))
        }
        let records = entries.compactMap(\.record)
        let quarantined = records.count < entries.count ? quarantine(url) : nil
        return (records.sorted { $0.createdAt > $1.createdAt }, quarantined)
    }

    /// Copies a damaged file to `<name>.corrupt-<timestamp>.json` beside it.
    nonisolated static func quarantine(_ url: URL, now: Date = Date()) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = url.deletingPathExtension().lastPathComponent
        var destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).corrupt-\(formatter.string(from: now)).json")
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = url.deletingLastPathComponent()
                .appendingPathComponent("\(base).corrupt-\(formatter.string(from: now))-\(suffix).json")
            suffix += 1
        }
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

/// One array element of `history.json`, decoded as forgivingly as possible.
private struct LossyRecord: Decodable {
    var record: HistoryRecord?

    init(from decoder: Decoder) throws {
        if let current = try? HistoryRecord(from: decoder) {
            record = current
        } else {
            record = try? LegacyRecord(from: decoder).record
        }
    }
}

/// Every field optional except the ones a record is meaningless without, for files written
/// before a field existed.
private struct LegacyRecord: Decodable {
    var id: UUID
    var createdAt: Date
    var context: AppContext?
    var style: WritingStyle?
    var engine: String?
    var rawText: String?
    var finalText: String?
    var polishedBy: PolishProvider?
    var corrections: [AppliedCorrection]?
    var snippets: [String]?
    var audioFileName: String?
    var audioDuration: Double?
    var timings: DictationTimings?
    var outcome: DictationOutcome?
    var errorMessage: String?

    var record: HistoryRecord {
        HistoryRecord(
            id: id, createdAt: createdAt, context: context, style: style, engine: engine ?? "",
            rawText: rawText ?? "", finalText: finalText ?? "", polishedBy: polishedBy,
            corrections: corrections ?? [], snippets: snippets ?? [], audioFileName: audioFileName,
            audioDuration: audioDuration ?? 0, timings: timings ?? DictationTimings(),
            outcome: outcome ?? .inserted, errorMessage: errorMessage)
    }
}
