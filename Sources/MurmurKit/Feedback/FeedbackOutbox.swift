import Foundation
import Observation

/// Feedback notes on disk, sent or waiting to be. A note is saved here before any attempt to
/// file it, so no connection, no token or a crash never loses what was said.
///
/// Layout under `directory`:
///
///     <id>.json   the note, its delivery state included
///     <id>.wav    its recording
@MainActor
@Observable
public final class FeedbackOutbox {
    /// Newest first.
    public private(set) var notes: [FeedbackNote] = []

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        notes = Self.load(from: directory)
    }

    /// An unsaved outbox, for previews, snapshots and tests.
    public init(previewNotes: [FeedbackNote]) {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedback-preview-\(UUID().uuidString)", isDirectory: true)
        notes = previewNotes.sorted { $0.createdAt > $1.createdAt }
    }

    /// Notes not filed yet, oldest first: the order they're sent in. A note whose recording
    /// couldn't be transcribed has no words to send and stays here, with its audio, instead.
    public var pending: [FeedbackNote] {
        Array(notes.filter { !$0.delivery.isSent && $0.hasWords }.reversed())
    }

    public func note(id: UUID) -> FeedbackNote? {
        notes.first { $0.id == id }
    }

    public func audioURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).wav")
    }

    /// Adds `note`, or replaces the saved one with the same id, and writes it out.
    @discardableResult
    public func save(_ note: FeedbackNote) -> Bool {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
            notes.sort { $0.createdAt > $1.createdAt }
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(note).write(to: fileURL(for: note.id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Removes a note and its recording (Esc while it was being said or transcribed).
    public func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(for: id))
        try? FileManager.default.removeItem(at: audioURL(for: id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private static func load(from directory: URL) -> [FeedbackNote] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(FeedbackNote.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
