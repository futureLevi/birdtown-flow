import Foundation
import Observation

/// The user's snippets, persisted as JSON.
@MainActor
@Observable
public final class SnippetStore {
    public private(set) var snippets: [Snippet] = []

    private let fileURL: URL?

    /// Triggers each snippet had before it was edited, by snippet id, so History's uses of
    /// the old trigger still count toward it (see `LibraryUsage`). Saved beside the snippets.
    public private(set) var aliases = UsageAliases()

    /// Deletes still inside their undo window. `snippets` keeps them until the window closes;
    /// lists hide them and dictation ignores them.
    public let deletion: UndoableDeletion

    /// Set when `snippets.json` couldn't be read and was copied aside before being replaced.
    public private(set) var quarantinedFile: URL?

    public init(fileURL: URL) {
        self.fileURL = fileURL
        deletion = UndoableDeletion()
        let loaded = Self.load(from: fileURL)
        snippets = loaded.snippets
        quarantinedFile = loaded.quarantined
        aliases = UsageAliases.load(from: Self.aliasesURL(beside: fileURL))
    }

    /// In-memory only — for previews, snapshots and tests.
    public init(preview: [Snippet]) {
        fileURL = nil
        deletion = UndoableDeletion()
        snippets = preview
    }

    /// What dictation expands: turned on, and not waiting out a delete's undo window.
    public var enabled: [Snippet] { snippets.filter { $0.isEnabled && !deletion.isPending($0.id) } }

    /// Every snippet except those waiting out a delete's undo window, in order.
    public var visible: [Snippet] { deletion.visible(snippets) }

    public func add(_ snippet: Snippet) {
        // Adding moves on from a delete, and may reuse its trigger: make that delete final.
        deletion.commit()
        snippets.insert(snippet, at: 0)
        save()
    }

    public func update(_ snippet: Snippet) {
        // Taking the trigger of a snippet waiting out its delete makes that delete final, so
        // Undo can't bring back a second snippet with the same trigger.
        let key = LibraryUsage.snippetKey(trigger: snippet.trigger)
        if snippets.contains(where: { deletion.isPending($0.id) && LibraryUsage.snippetKey(trigger: $0.trigger) == key }) {
            deletion.commit()
        }
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let previous = snippets[index]
        snippets[index] = snippet
        let oldKey = LibraryUsage.snippetKey(trigger: previous.trigger)
        let newKey = LibraryUsage.snippetKey(trigger: snippet.trigger)
        if oldKey != newKey {
            aliases.renamed(owner: snippet.id.uuidString, from: oldKey, to: newKey)
            saveAliases()
        }
        save()
    }

    /// Removes snippets for good, at once. The pages use `delete(ids:undoWindow:)`.
    public func delete(ids: Set<UUID>) {
        snippets.removeAll { ids.contains($0.id) }
        let hadAliases = ids.contains { !aliases.formerKeys(of: $0.uuidString).isEmpty }
        for id in ids { aliases.remove(owner: id.uuidString) }
        if hadAliases { saveAliases() }
        save()
    }

    /// Hides `ids` now and deletes them once `undoWindow` passes, unless `undoDeletion()`
    /// brings them back first. A delete already waiting is committed first.
    public func delete(ids: Set<UUID>, undoWindow: Duration) {
        let ids = ids.filter { id in snippets.contains { $0.id == id } }
        deletion.delete(ids, after: undoWindow) { [weak self] in self?.delete(ids: $0) }
    }

    /// Brings back the last delete, if its undo window is still open.
    public func undoDeletion() {
        deletion.undo()
    }

    /// Finishes a delete still waiting out its undo window.
    public func commitDeletion() {
        deletion.commit()
    }

    /// Another snippet already uses this trigger (case-insensitive), excluding `id` and any
    /// snippet waiting out a delete (adding a snippet makes that delete final).
    public func hasConflict(trigger: String, excluding id: UUID? = nil) -> Bool {
        let key = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return false }
        return visible.contains { $0.id != id && $0.trigger.lowercased() == key }
    }

    private static func aliasesURL(beside fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("snippet-usage.json")
    }

    private func saveAliases() {
        guard let fileURL else { return }
        aliases.save(to: Self.aliasesURL(beside: fileURL))
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
