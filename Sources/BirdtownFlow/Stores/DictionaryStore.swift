import MurmurDictionary
import MurmurKit
import Foundation
import Observation

/// The dictionary, persisted as a plain text file you can edit by hand.
///
/// A text file rather than JSON, because the spec asks for something editable outside the UI
/// and JSON is only nominally that — quoting, escaping and a trailing-comma trap for anyone
/// adding a line in a hurry. The format is one entry per line:
///
/// ```
/// Anthropic
/// Vercel
/// cloud code -> Claude Code
/// # off: whisper flow -> Wispr Flow
/// ```
///
/// A bare line is a term. `X -> Y` is a correction. `#` starts a comment, and a disabled
/// entry is written as a `# off:` comment so it survives a round trip through the file
/// without silently disappearing.
///
/// The file is watched, so editing it in a text editor updates the UI live and vice versa.
@MainActor
@Observable
final class DictionaryStore {
    static let shared = DictionaryStore()

    private(set) var entries: [DictionaryEntry] = []

    /// Bumped whenever entries change. `corrector` and `biasPhrases` are cached against it,
    /// so every path that changes `entries` must bump it.
    private(set) var revision = 0

    /// Keys each replacement had before it was edited, so History's uses of the old wording
    /// still count toward it (see `LibraryUsage`). Saved beside the dictionary, keyed by the
    /// replacement's current key: the text file has no ids to keep.
    private(set) var aliases = UsageAliases()

    /// Deletes still inside their undo window. `entries` keeps them until the window
    /// closes; the page hides them and dictation ignores them.
    let deletion: UndoableDeletion

    private var watcher: DispatchSourceFileSystemObject?
    /// Exactly what we last wrote (or read), so our own save — which the watcher only sees
    /// after `save()` has returned — doesn't read back as an external edit.
    @ObservationIgnored private var lastWrittenText: String?
    @ObservationIgnored private var cachedCorrector: (rev: Int, value: DictionaryCorrector)?
    @ObservationIgnored private var cachedBiasPhrases: (rev: Int, value: [String])?
    /// `false` for in-memory stores (previews, snapshots), which must never touch the
    /// user's real dictionary file.
    @ObservationIgnored private var persists = true

    static var fileURL: URL {
        AppPaths.support.appendingPathComponent("dictionary.txt")
    }

    static var aliasesURL: URL {
        AppPaths.support.appendingPathComponent("dictionary-usage.json")
    }

    private init() {
        deletion = UndoableDeletion()
        load()
        aliases = UsageAliases.load(from: Self.aliasesURL)
        startWatching()
    }

    /// In-memory only — for previews and snapshots. Never reads, writes or watches the file.
    init(preview entries: [DictionaryEntry]) {
        deletion = UndoableDeletion()
        persists = false
        self.entries = entries
        revision = 1
    }

    // MARK: - Editing

    func add(_ entry: DictionaryEntry) {
        // Adding moves on from a delete, and may reuse its wording: make that delete final.
        deletion.commit()
        entries.append(entry)
        save()
    }

    func update(_ entry: DictionaryEntry) {
        // Taking the wording of an entry waiting out its delete makes that delete final, so
        // Undo can't bring back a duplicate (the editor ignores pending entries when it
        // checks for clashes).
        if entries.contains(where: { $0.id != entry.id && deletion.isPending($0.id) && Self.clashes($0, entry) }) {
            deletion.commit()
        }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let previous = entries[index]
        entries[index] = entry
        recordRename(from: previous, to: entry)
        save()
    }

    /// Removes an entry for good, at once. The page uses `delete(ids:undoWindow:)`.
    func delete(_ entry: DictionaryEntry) {
        delete(ids: [entry.id])
    }

    /// Removes entries for good, at once.
    func delete(ids: Set<UUID>) {
        for entry in entries where ids.contains(entry.id) && entry.kind == .correction {
            aliases.remove(owner: Self.usageKey(entry))
        }
        entries.removeAll { ids.contains($0.id) }
        saveAliases()
        save()
    }

    /// Hides `ids` now and deletes them once `undoWindow` passes, unless `undoDeletion()`
    /// brings them back first. A delete already waiting is committed first.
    func delete(ids: Set<UUID>, undoWindow: Duration) {
        let ids = ids.filter { id in entries.contains { $0.id == id } }
        guard !ids.isEmpty else { return }
        deletion.delete(ids, after: undoWindow) { [weak self] in self?.delete(ids: $0) }
        revision += 1
    }

    /// Brings back the last delete, if its undo window is still open.
    func undoDeletion() {
        guard !deletion.pending.isEmpty else { return }
        deletion.undo()
        revision += 1
    }

    /// Finishes a delete still waiting out its undo window.
    func commitDeletion() {
        deletion.commit()
    }

    /// Every entry except those waiting out a delete's undo window, in order.
    var visible: [DictionaryEntry] { deletion.visible(entries) }

    /// Case- and diacritic-insensitive search across both sides of an entry. Entries waiting
    /// out a delete's undo window are left out.
    func filtered(by query: String) -> [DictionaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visible }
        return visible.filter {
            $0.write.localizedStandardContains(trimmed) || $0.hear.localizedStandardContains(trimmed)
        }
    }

    /// A corrector over the current entries, leaving out those waiting out a delete's undo
    /// window. Built once per `revision` rather than per dictation — it compiles a regex per
    /// rule, on the main actor, between key-up and insert. A pending delete, an undo and the
    /// final removal all bump `revision`, so the cache never sees a stale set of entries.
    var corrector: DictionaryCorrector {
        if let cached = cachedCorrector, cached.rev == revision { return cached.value }
        let value = DictionaryCorrector(entries: visible)
        cachedCorrector = (revision, value)
        return value
    }

    /// Vocabulary for the engine, leaving out entries waiting out a delete. Cached per `revision`.
    var biasPhrases: [String] {
        if let cached = cachedBiasPhrases, cached.rev == revision { return cached.value }
        let value = DictionaryCorrector.biasPhrases(from: visible)
        cachedBiasPhrases = (revision, value)
        return value
    }

    // MARK: - Usage

    /// How many times each replacement has changed a dictation in `records`, by entry id.
    func usageCounts(in records: [HistoryRecord]) -> [UUID: Int] {
        LibraryUsage.correctionCounts(entries: entries, aliases: aliases, records: records)
    }

    /// The key History's corrections are matched against; only replacements have one.
    private static func usageKey(_ entry: DictionaryEntry) -> String {
        LibraryUsage.correctionKey(hear: entry.hear, write: entry.write)
    }

    /// The clashes the editor refuses: the same term twice, or two replacements for the same
    /// heard text.
    private static func clashes(_ a: DictionaryEntry, _ b: DictionaryEntry) -> Bool {
        guard a.kind == b.kind else { return false }
        switch a.kind {
        case .term: return a.write.caseInsensitiveCompare(b.write) == .orderedSame
        case .correction: return a.hear.caseInsensitiveCompare(b.hear) == .orderedSame
        }
    }

    /// Carries a replacement's history across an edit to either side.
    private func recordRename(from previous: DictionaryEntry, to entry: DictionaryEntry) {
        guard previous.kind == .correction else { return }
        let oldKey = Self.usageKey(previous)
        guard entry.kind == .correction else {
            aliases.remove(owner: oldKey)
            saveAliases()
            return
        }
        let newKey = Self.usageKey(entry)
        guard oldKey != newKey else { return }
        aliases.renamed(owner: oldKey, from: oldKey, to: newKey, newOwner: newKey)
        saveAliases()
    }

    // MARK: - Persistence

    private func load() {
        guard let text = try? String(contentsOf: Self.fileURL, encoding: .utf8) else {
            lastWrittenText = nil
            entries = []
            revision += 1
            return
        }
        // Our own save echoing back through the watcher: nothing changed.
        guard text != lastWrittenText else { return }
        lastWrittenText = text

        // Keep the ids of entries that didn't change, so a hand edit doesn't rebuild every row
        // and an open editor, a pending delete or a selection can still find its entry.
        let parsed = Self.keepingIDs(of: entries, in: Self.parse(text))
        guard parsed != entries else { return }  // e.g. only a comment changed
        entries = parsed
        revision += 1
    }

    /// The file has no ids, so every read makes new ones. An entry that's still there after
    /// a reload keeps the id it had, so an open editor, a pending delete or a selection
    /// still finds it.
    static func keepingIDs(of old: [DictionaryEntry], in new: [DictionaryEntry]) -> [DictionaryEntry] {
        guard !old.isEmpty else { return new }
        var available: [String: [UUID]] = [:]
        for entry in old {
            available[identity(entry), default: []].append(entry.id)
        }
        return new.map { entry in
            var entry = entry
            let key = identity(entry)
            if var ids = available[key], !ids.isEmpty {
                entry.id = ids.removeFirst()
                available[key] = ids
            }
            return entry
        }
    }

    private static func identity(_ entry: DictionaryEntry) -> String {
        "\(entry.kind.rawValue)\u{1F}\(entry.hear)\u{1F}\(entry.write)"
    }

    static func parse(_ text: String) -> [DictionaryEntry] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }

            // `# off:` is a disabled entry; any other comment is just a comment.
            var isEnabled = true
            if line.hasPrefix("#") {
                let stripped = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard stripped.lowercased().hasPrefix("off:") else { return nil }
                line = stripped.dropFirst(4).trimmingCharacters(in: .whitespaces)
                isEnabled = false
                guard !line.isEmpty else { return nil }
            }

            if let arrow = line.range(of: "->") {
                let hear = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let write = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !hear.isEmpty, !write.isEmpty else { return nil }
                return DictionaryEntry(kind: .correction, write: write, hear: hear, isEnabled: isEnabled)
            }

            return DictionaryEntry(kind: .term, write: line, isEnabled: isEnabled)
        }
    }

    private func save() {
        revision += 1
        guard persists else { return }

        let body = entries.map(\.fileLine).joined(separator: "\n")
        let text = Self.header + body + "\n"
        do {
            try text.write(to: Self.fileURL, atomically: true, encoding: .utf8)
            lastWrittenText = text
        } catch {}
    }

    /// Writes the aliases, dropping any whose replacement is gone (edited or deleted in the
    /// text file, where no rename can be seen).
    private func saveAliases() {
        let owners = Set(entries.filter { $0.kind == .correction }.map(Self.usageKey))
        aliases.prune(keeping: owners)
        guard persists else { return }
        aliases.save(to: Self.aliasesURL)
    }

    private static let header = """
        # Birdtown Flow dictionary
        #
        #   Anthropic                 a term — the engine is told this word exists
        #   cloud code -> Claude Code a correction — when you hear X, write Y
        #   # off: some rule -> Rule  a disabled entry
        #
        # Edit this file directly if you like; the app picks up changes immediately.

        """

    // MARK: - External edits

    /// Watches the file so a hand edit shows up in the UI without a relaunch.
    ///
    /// Rearms after every event: an atomic write replaces the inode, so the descriptor we
    /// were watching is gone the moment the file changes — including when *we* save.
    private func startWatching() {
        watcher?.cancel()
        watcher = nil

        // No file yet: watch its folder instead, so a dictionary.txt created in a text editor
        // or Terminal is picked up too, not just one the app wrote first.
        let exists = FileManager.default.fileExists(atPath: Self.fileURL.path)
        let watched = exists ? Self.fileURL : Self.fileURL.deletingLastPathComponent()
        let descriptor = open(watched.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            // A folder event is any file in it changing; only reload once ours exists.
            let appeared = !exists && FileManager.default.fileExists(atPath: Self.fileURL.path)
            // `load()` ignores our own saves by content — a timing flag can't, since this
            // handler only runs after `save()` has returned.
            if exists || appeared { self.load() }
            if exists || appeared { self.startWatching() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        watcher = source
    }
}
