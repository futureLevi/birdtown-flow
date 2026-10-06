import Foundation
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

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        records = Self.load(from: fileURL)
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

    // MARK: - Mutations

    public func add(_ record: HistoryRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        records.sort { $0.createdAt > $1.createdAt }
        scheduleSave()
    }

    public func update(_ record: HistoryRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            add(record)
            return
        }
        records[index] = record
        scheduleSave()
    }

    public func delete(ids: Set<UUID>) {
        for record in records where ids.contains(record.id) {
            removeAudio(of: record)
        }
        records.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    public func deleteAll() {
        for record in records { removeAudio(of: record) }
        records.removeAll()
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
        if changed { scheduleSave() }
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    nonisolated private static func load(from url: URL) -> [HistoryRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = (try? decoder.decode([HistoryRecord].self, from: data)) ?? []
        return records.sorted { $0.createdAt > $1.createdAt }
    }
}
