import Foundation
import Observation

/// The user's snippets, persisted as JSON.
@MainActor
@Observable
public final class SnippetStore {
    public private(set) var snippets: [Snippet] = []

    private let fileURL: URL?

    /// Set when `snippets.json` couldn't be read and was copied aside before being replaced.
    public private(set) var quarantinedFile: URL?

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let loaded = Self.load(from: fileURL)
        snippets = loaded.snippets
        quarantinedFile = loaded.quarantined
    }

    /// In-memory only — for previews, snapshots and tests.
    public init(preview: [Snippet]) {
        fileURL = nil
        snippets = preview
    }

    public var enabled: [Snippet] { snippets.filter(\.isEnabled) }

    public func add(_ snippet: Snippet) {
        snippets.insert(snippet, at: 0)
        save()
    }

    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    public func delete(ids: Set<UUID>) {
        snippets.removeAll { ids.contains($0.id) }
        save()
    }

    /// Another snippet already uses this trigger (case-insensitive), excluding `id`.
    public func hasConflict(trigger: String, excluding id: UUID? = nil) -> Bool {
        let key = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return false }
        return snippets.contains { $0.id != id && $0.trigger.lowercased() == key }
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snippets) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// A file that exists but won't decode is copied aside first, so the next save can never
    /// silently overwrite snippets the user spent time writing.
    private static func load(from url: URL) -> (snippets: [Snippet], quarantined: URL?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], nil) }
        guard let data = try? Data(contentsOf: url) else { return ([], HistoryStore.quarantine(url)) }
        if data.isEmpty { return ([], nil) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snippets = try? decoder.decode([Snippet].self, from: data) else {
            return ([], HistoryStore.quarantine(url))
        }
        return (snippets, nil)
    }
}
