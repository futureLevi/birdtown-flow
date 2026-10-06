import Foundation
import Observation

/// The user's snippets, persisted as JSON.
@MainActor
@Observable
public final class SnippetStore {
    public private(set) var snippets: [Snippet] = []

    private let fileURL: URL?

    public init(fileURL: URL) {
        self.fileURL = fileURL
        snippets = Self.load(from: fileURL)
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

    private static func load(from url: URL) -> [Snippet] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Snippet].self, from: data)) ?? []
    }
}
