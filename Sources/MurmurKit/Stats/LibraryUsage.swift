import Foundation
import MurmurDictionary

/// How often each dictionary replacement and each snippet has fired, counted from History.
///
/// History records what fired as text: a correction's `from`/`to` and a snippet's trigger.
/// Counting by that text alone (as the pages once did) goes wrong in two ways, and these
/// counts are the only sign a rule is working, so both matter:
///
/// - **Edits reset the count.** Reword a snippet's trigger and its old uses no longer match
///   it. Each item therefore carries its *former* keys (`UsageAliases`, saved beside the
///   store), and an edit adds the old key to them.
/// - **Shared text merges counts.** "cloud → Claude" and "clawed → Claude" both write
///   "Claude". A correction is matched on what was heard *and* what was written, using the
///   same leniency as the corrector (case, spaces and hyphens), and only falls back to the
///   written side when exactly one replacement could have written it.
///
/// `Use.id` lets a record name its item directly. History doesn't store ids yet; when it
/// does, those uses are counted by id and everything else keeps working by text.
public enum LibraryUsage {
    /// Something that can be used: a replacement or a snippet.
    public struct Item: Sendable, Equatable {
        public var id: UUID
        /// What identifies it now.
        public var key: String
        /// What identified it before it was edited, oldest first.
        public var formerKeys: [String]
        /// A looser key, matched only when no item claims a use by `key`, and only when it
        /// picks out a single item.
        public var fallbackKey: String?
        /// Uses before this can't be its own (a new snippet reusing a deleted one's trigger).
        public var since: Date?

        public init(id: UUID, key: String, formerKeys: [String] = [], fallbackKey: String? = nil, since: Date? = nil) {
            self.id = id
            self.key = key
            self.formerKeys = formerKeys
            self.fallbackKey = fallbackKey
            self.since = since
        }
    }

    /// One firing recorded in History.
    public struct Use: Sendable, Equatable {
        public var id: UUID?
        public var key: String
        public var fallbackKey: String?
        public var count: Int
        public var date: Date

        public init(id: UUID? = nil, key: String, fallbackKey: String? = nil, count: Int = 1, date: Date) {
            self.id = id
            self.key = key
            self.fallbackKey = fallbackKey
            self.count = count
            self.date = date
        }
    }

    // MARK: - Keys

    /// Case-insensitive, NFC, with spaces and hyphens removed: the corrector matches
    /// "cloud code" in "CloudCode" and "cloud-code", so they're the same phrase here too.
    public static func spokenKey(_ text: String) -> String {
        let folded = text.precomposedStringWithCanonicalMapping.lowercased()
        let kept = folded.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "-" }
        let key = String(String.UnicodeScalarView(kept))
        return key.isEmpty ? folded : key
    }

    /// What a replacement writes, compared case-insensitively.
    public static func writtenKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// A replacement, by both sides.
    public static func correctionKey(hear: String, write: String) -> String {
        spokenKey(hear) + "\u{1F}" + writtenKey(write)
    }

    /// A snippet, by its trigger.
    public static func snippetKey(trigger: String) -> String {
        writtenKey(trigger)
    }

    // MARK: - Items and uses

    /// The replacements among `entries` (terms never fire), with their former keys.
    public static func items(for entries: [DictionaryEntry], aliases: UsageAliases) -> [Item] {
        entries.filter { $0.kind == .correction }.map { entry in
            let key = correctionKey(hear: entry.hear, write: entry.write)
            return Item(id: entry.id, key: key, formerKeys: aliases.formerKeys(of: key), fallbackKey: writtenKey(entry.write))
        }
    }

    /// Snippets, with their former triggers. `aliases` is keyed by the snippet's id.
    public static func items(for snippets: [Snippet], aliases: UsageAliases) -> [Item] {
        snippets.map { snippet in
            Item(
                id: snippet.id,
                key: snippetKey(trigger: snippet.trigger),
                formerKeys: aliases.formerKeys(of: snippet.id.uuidString),
                since: snippet.createdAt
            )
        }
    }

    /// Every correction History recorded, weighted by how many times it fired.
    public static func correctionUses(in records: [HistoryRecord]) -> [Use] {
        records.flatMap { record in
            record.corrections.map {
                Use(key: correctionKey(hear: $0.from, write: $0.to), fallbackKey: writtenKey($0.to),
                    count: $0.count, date: record.createdAt)
            }
        }
    }

    /// Every snippet History recorded expanding, once per dictation.
    public static func snippetUses(in records: [HistoryRecord]) -> [Use] {
        records.flatMap { record in
            record.snippets.map { Use(key: snippetKey(trigger: $0), date: record.createdAt) }
        }
    }

    // MARK: - Counting

    /// How many times each item was used. Items never used are absent.
    public static func tally(_ uses: [Use], items: [Item]) -> [UUID: Int] {
        var byID: [UUID: Item] = [:]
        var byKey: [String: [Item]] = [:]
        var byFormerKey: [String: [Item]] = [:]
        var byFallback: [String: [Item]] = [:]
        for item in items {
            byID[item.id] = item
            byKey[item.key, default: []].append(item)
            for former in item.formerKeys where former != item.key {
                byFormerKey[former, default: []].append(item)
            }
            if let fallback = item.fallbackKey {
                byFallback[fallback, default: []].append(item)
            }
        }

        func eligible(_ candidates: [Item]?, at date: Date) -> [Item] {
            (candidates ?? []).filter { $0.since.map { date >= $0 } ?? true }
        }

        var counts: [UUID: Int] = [:]
        for use in uses {
            let owner: UUID?
            if let id = use.id, byID[id] != nil {
                owner = id
            } else if let current = eligible(byKey[use.key], at: use.date).first {
                owner = current.id
            } else if let former = eligible(byFormerKey[use.key], at: use.date).last {
                // The most recently added alias: the item that held this key last.
                owner = former.id
            } else if let fallback = use.fallbackKey {
                let candidates = eligible(byFallback[fallback], at: use.date)
                // Shared by several replacements: there's no telling which, so count none
                // rather than credit every one of them.
                owner = candidates.count == 1 ? candidates[0].id : nil
            } else {
                owner = nil
            }
            if let owner { counts[owner, default: 0] += use.count }
        }
        return counts
    }

    /// Uses per replacement, keyed by entry id.
    public static func correctionCounts(
        entries: [DictionaryEntry], aliases: UsageAliases, records: [HistoryRecord]
    ) -> [UUID: Int] {
        tally(correctionUses(in: records), items: items(for: entries, aliases: aliases))
    }

    /// Uses per snippet, keyed by snippet id.
    public static func snippetCounts(
        snippets: [Snippet], aliases: UsageAliases, records: [HistoryRecord]
    ) -> [UUID: Int] {
        tally(snippetUses(in: records), items: items(for: snippets, aliases: aliases))
    }
}

/// Keys an item was known by before it was edited, so its History still counts toward it.
///
/// Owners are whatever identifies an item stably: a snippet's id, or a replacement's current
/// key (dictionary entries live in a plain text file, which has no ids to keep).
public struct UsageAliases: Codable, Sendable, Equatable {
    /// Owner → former keys, oldest first.
    public private(set) var former: [String: [String]]

    /// Enough to keep a rule's history through any realistic run of edits.
    public static let limit = 20

    public init(former: [String: [String]] = [:]) {
        self.former = former
    }

    public func formerKeys(of owner: String) -> [String] {
        former[owner] ?? []
    }

    /// The item `owner` used to be known as `oldKey` and is now known as `newKey`.
    /// For owners that are themselves the key (replacements), pass `newOwner` too.
    public mutating func renamed(owner: String, from oldKey: String, to newKey: String, newOwner: String? = nil) {
        var keys = former.removeValue(forKey: owner) ?? []
        if oldKey != newKey {
            keys.removeAll { $0 == oldKey || $0 == newKey }
            keys.append(oldKey)
        } else {
            keys.removeAll { $0 == newKey }
        }
        if keys.count > Self.limit { keys.removeFirst(keys.count - Self.limit) }
        let target = newOwner ?? owner
        if !keys.isEmpty { former[target] = keys }
    }

    /// Forgets an item that was deleted.
    public mutating func remove(owner: String) {
        former.removeValue(forKey: owner)
    }

    /// Keeps only owners still present, dropping those of items deleted outside the app.
    public mutating func prune(keeping owners: Set<String>) {
        former = former.filter { owners.contains($0.key) }
    }

    // MARK: - Persistence

    /// The aliases at `url`; empty when missing or unreadable (they only refine counts).
    public static func load(from url: URL) -> UsageAliases {
        guard let data = try? Data(contentsOf: url),
              let aliases = try? JSONDecoder().decode(UsageAliases.self, from: data)
        else { return UsageAliases() }
        return aliases
    }

    public func save(to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
