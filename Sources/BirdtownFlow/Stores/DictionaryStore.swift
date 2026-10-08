import MurmurDictionary
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

    private init() {
        load()
        startWatching()
    }

    /// In-memory only — for previews and snapshots. Never reads, writes or watches the file.
    init(preview entries: [DictionaryEntry]) {
        persists = false
        self.entries = entries
        revision = 1
    }

    // MARK: - Editing

    func add(_ entry: DictionaryEntry) {
        entries.append(entry)
        save()
    }

    func update(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func delete(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func delete(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    /// Case- and diacritic-insensitive search across both sides of an entry.
    func filtered(by query: String) -> [DictionaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.write.localizedStandardContains(trimmed) || $0.hear.localizedStandardContains(trimmed)
        }
    }

    /// A corrector over the current entries. Built once per `revision` rather than per
    /// dictation — it compiles a regex per rule, on the main actor, between key-up and insert.
    var corrector: DictionaryCorrector {
        if let cached = cachedCorrector, cached.rev == revision { return cached.value }
        let value = DictionaryCorrector(entries: entries)
        cachedCorrector = (revision, value)
        return value
    }

    var biasPhrases: [String] {
        if let cached = cachedBiasPhrases, cached.rev == revision { return cached.value }
        let value = DictionaryCorrector.biasPhrases(from: entries)
        cachedBiasPhrases = (revision, value)
        return value
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
        // and an open edit sheet can still find its entry.
        let parsed = DictionaryEntry.carryingIDs(from: entries, into: Self.parse(text))
        guard parsed != entries else { return }  // e.g. only a comment changed
        entries = parsed
        revision += 1
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
