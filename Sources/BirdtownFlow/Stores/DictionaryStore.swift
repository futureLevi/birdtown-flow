import MurmurDictionary
import MurmurKit
import Foundation
import Observation

/// The user's dictionary, kept in `dictionary.txt` so it can be changed in any text editor.
///
/// Plain lines rather than JSON on purpose: someone adding a word by hand shouldn't have to
/// get quotes, escapes and commas right. Each line is one entry:
///
/// ```
/// Birdtown
/// bird town -> Birdtown
/// # off: para keet -> Parakeet
/// ```
///
/// A line on its own is a term, and `heard -> written` is a correction. Lines starting with
/// `#` are notes and are skipped, except `# off:`, which holds a switched-off entry: turning
/// an entry off in the app keeps it in the file instead of deleting it.
///
/// While the app runs, edits go both ways: saving the file updates the Dictionary screen,
/// and changes made in the app are written straight back to the file.
@MainActor
@Observable
final class DictionaryStore {
    static let shared = DictionaryStore()

    static var fileURL: URL {
        AppPaths.support.appendingPathComponent("dictionary.txt")
    }

    static var aliasesURL: URL {
        AppPaths.support.appendingPathComponent("dictionary-usage.json")
    }

    /// Every entry in file order, including any still inside a delete's undo window; most
    /// callers want `visible`.
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

    /// What's watching the file (or, until the file exists, its folder) for outside edits.
    @ObservationIgnored private var fileWatch: DispatchSourceFileSystemObject?
    /// Exactly what we last wrote (or read), so our own save — which the watcher only sees
    /// after `save()` has returned — doesn't read back as an external edit.
    @ObservationIgnored private var lastWrittenText: String?
    @ObservationIgnored private var cachedCorrector: (rev: Int, value: DictionaryCorrector)?
    @ObservationIgnored private var cachedBiasPhrases: (rev: Int, value: [String])?
    /// `false` for in-memory stores (previews, snapshots), which must never touch the
    /// user's real dictionary file.
    @ObservationIgnored private var persists = true

    private init() {
        deletion = UndoableDeletion()
        reloadFromDisk()
        aliases = UsageAliases.load(from: Self.aliasesURL)
        watchFile()
    }

    /// In-memory only — for previews and snapshots. Never reads, writes or watches the file.
    init(preview entries: [DictionaryEntry]) {
        deletion = UndoableDeletion()
        persists = false
        self.entries = entries
        revision = 1
    }

    // MARK: - Changing entries

    func add(_ entry: DictionaryEntry) {
        // Adding moves on from a delete, and may reuse its wording: make that delete final.
        deletion.commit()
        entries.append(entry)
        save()
    }

    /// Replaces the entry that has `entry`'s id. Does nothing if that entry is gone.
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
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return visible }
        return visible.filter { entry in
            [entry.write, entry.hear].contains { $0.localizedStandardContains(needle) }
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

    // MARK: - Reading and writing

    /// Reads the file again: at launch, and whenever it changes underneath us. A missing or
    /// unreadable file is an empty dictionary.
    private func reloadFromDisk() {
        guard let text = try? String(contentsOf: Self.fileURL, encoding: .utf8) else {
            lastWrittenText = nil
            replaceEntries(with: [])
            return
        }
        // Our own save echoing back through the watcher: nothing changed.
        guard text != lastWrittenText else { return }
        lastWrittenText = text

        // Keep the ids of entries that didn't change, so a hand edit doesn't rebuild every row
        // and an open editor, a pending delete or a selection can still find its entry.
        let parsed = Self.keepingIDs(of: entries, in: Self.parse(text))
        guard parsed != entries else { return }  // e.g. only a comment changed
        replaceEntries(with: parsed)
    }

    private func replaceEntries(with new: [DictionaryEntry]) {
        entries = new
        revision += 1
    }

    /// Call after every change to `entries`: bumps `revision`, then writes the file (unless
    /// this is an in-memory store).
    private func save() {
        revision += 1
        guard persists else { return }
        let text = Self.fileText(for: entries)
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

    // MARK: - File format

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

    /// Reads entries from the file's text. Blank lines, notes and lines that don't make a
    /// whole entry (`-> Birdtown`, a bare `# off:`) are skipped.
    static func parse(_ text: String) -> [DictionaryEntry] {
        text.split(separator: "\n").compactMap { line in
            entry(from: line.trimmingCharacters(in: .whitespaces))
        }
    }

    /// One trimmed line as an entry, or `nil` when it isn't one.
    private static func entry(from line: String) -> DictionaryEntry? {
        var body = line
        var isEnabled = true
        if body.hasPrefix("#") {
            guard let switchedOff = switchedOffEntry(inNote: body) else { return nil }
            body = switchedOff
            isEnabled = false
        }
        guard !body.isEmpty else { return nil }

        guard let separator = body.range(of: "->") else {
            return DictionaryEntry(kind: .term, write: body, isEnabled: isEnabled)
        }
        let heard = body[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        let written = body[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !heard.isEmpty, !written.isEmpty else { return nil }
        return DictionaryEntry(kind: .correction, write: written, hear: heard, isEnabled: isEnabled)
    }

    /// The entry text of a `# off:` line (the marker in any case), or `nil` for an ordinary note.
    private static func switchedOffEntry(inNote line: String) -> String? {
        let note = line.dropFirst().trimmingCharacters(in: .whitespaces)
        let marker = "off:"
        guard note.lowercased().hasPrefix(marker) else { return nil }
        return note.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    }

    /// What `save()` writes: the header, then one line per entry, in order.
    private static func fileText(for entries: [DictionaryEntry]) -> String {
        header + entries.map(\.fileLine).joined(separator: "\n") + "\n"
    }

    /// A reminder of the format at the top of the file. Every line is a note, so reading it
    /// back adds nothing.
    private static let header = """
        # Birdtown Flow dictionary. One entry per line:
        #
        #   Birdtown                        a word, spelled the way you want it
        #   bird town -> Birdtown           when you say the left side, write the right
        #   # off: bird town -> Birdtown    switched off, kept for later
        #
        # Other lines starting with # are skipped. Save, and the app picks up your changes.

        """

    // MARK: - Outside edits

    /// Written to, grown, replaced or removed: anything that can mean new contents.
    private static let watchedChanges: DispatchSource.FileSystemEvent = [.write, .extend, .rename, .delete]

    /// Watches for the file being changed by something other than the app.
    ///
    /// Saving replaces the file with a new one (ours too: `save()` writes atomically), and
    /// the descriptor being watched still points at the old one, so the watch is set up
    /// again after every change. Until the file exists its folder is watched instead, so a
    /// dictionary.txt made in an editor or Terminal is noticed as well.
    private func watchFile() {
        fileWatch?.cancel()
        fileWatch = nil

        let fileExisted = FileManager.default.fileExists(atPath: Self.fileURL.path)
        let target = fileExisted ? Self.fileURL : Self.fileURL.deletingLastPathComponent()
        let descriptor = open(target.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: Self.watchedChanges, queue: .main)
        source.setEventHandler { [weak self] in
            self?.watchedPathChanged(fileExisted: fileExisted)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileWatch = source
    }

    private func watchedPathChanged(fileExisted: Bool) {
        // While the folder is watched, any file in it changing lands here; act only once the
        // dictionary itself is there.
        guard fileExisted || FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        // `reloadFromDisk()` ignores our own saves by content — a timing flag can't, since
        // this handler only runs after `save()` has returned.
        reloadFromDisk()
        watchFile()
    }
}
