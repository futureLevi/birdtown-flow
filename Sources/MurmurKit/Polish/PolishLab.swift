import Foundation
import Observation

// The Lab: named polish configurations that can be tested side by side and then put to work
// for chosen writing styles, before anything changes for everyone.

/// How much the model may deliberate. `.standard` leaves it to the model.
public enum PolishEffort: String, Codable, CaseIterable, Sendable, Identifiable {
    case standard
    case low
    case medium
    case high
    case max

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: "Model default"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Max"
        }
    }

    /// For a segmented control.
    public var shortTitle: String { self == .standard ? "Default" : title }

    /// For the API's `output_config.effort` and Claude Code's `--effort`; `nil` leaves it out.
    public var value: String? { self == .standard ? nil : rawValue }
}

/// A named way to polish: who does it, with which model and effort, and the instructions.
public struct PolishConfiguration: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// What this version tries, in the person's words ("shorter examples").
    public var notes: String
    public var provider: PolishProvider
    /// The model for Claude Code, the Anthropic API and OpenAI-compatible endpoints. Apple
    /// Intelligence has one model and ignores it.
    public var model: String
    public var effort: PolishEffort
    /// The system prompt, with `PolishPlaceholder`s filled in per dictation. The dictation
    /// follows it, fenced in `<transcript>` tags.
    public var instructions: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), name: String, notes: String = "", provider: PolishProvider, model: String,
        effort: PolishEffort, instructions: String, updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.provider = provider
        self.model = model
        self.effort = effort
        self.instructions = instructions
        self.updatedAt = updatedAt
    }

    /// Fields added later decode with defaults, so an older lab.json still opens.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        provider = (try? container.decodeIfPresent(PolishProvider.self, forKey: .provider)) ?? .claudeCode
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel(for: provider)
        effort = (try? container.decodeIfPresent(PolishEffort.self, forKey: .effort)) ?? .standard
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    /// The model each provider starts with.
    public static func defaultModel(for provider: PolishProvider) -> String {
        switch provider {
        case .claudeCode, .anthropic: AnthropicClient.defaultModel
        case .openAICompatible: "gpt-4.1-mini"
        case .appleIntelligence, .off: ""
        }
    }

    /// Models offered in the Lab's menu; any other name can be typed.
    public static func suggestedModels(for provider: PolishProvider) -> [String] {
        switch provider {
        case .claudeCode, .anthropic: ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-4-5"]
        case .openAICompatible, .appleIntelligence, .off: []
        }
    }

    /// Providers a configuration can use: everything but Off.
    public static let providers: [PolishProvider] = PolishProvider.allCases.filter { $0 != .off }

    /// Next to Claude Code, plain "Claude" for the API is ambiguous.
    public static func providerTitle(_ provider: PolishProvider) -> String {
        provider == .anthropic ? "Claude API" : provider.title
    }

    /// Whether the provider takes a model name and an effort level.
    public var usesModel: Bool { provider != .appleIntelligence && provider != .off }
    public var usesEffort: Bool { provider == .claudeCode || provider == .anthropic }

    /// "Claude Code · claude-haiku-5-5 · Low effort"
    public var summary: String {
        var parts = [Self.providerTitle(provider)]
        if usesModel, !model.isEmpty { parts.append(model) }
        if usesEffort { parts.append(effort == .standard ? "Default effort" : "\(effort.title) effort") }
        return parts.joined(separator: " · ")
    }

    /// Whether two versions would polish the same way: everything but when they were saved.
    public func hasSameSetup(as other: PolishConfiguration) -> Bool {
        name == other.name && notes == other.notes && provider == other.provider && model == other.model
            && effort == other.effort && instructions == other.instructions
    }

    /// A blank-ish start: the light edit on Claude Code with Haiku 5.5 at low effort.
    public static func untitled(named name: String = "Untitled") -> PolishConfiguration {
        PolishConfiguration(
            name: name, provider: .claudeCode, model: AnthropicClient.defaultModel, effort: .low,
            instructions: PolishPrompt.fillerWordsTemplate)
    }

    /// Starting points: the app's two built-in prompts, on Claude Code with Haiku 5.5 at low
    /// effort, ready to copy and tune.
    public static func starters(now: Date = Date()) -> [PolishConfiguration] {
        [
            PolishConfiguration(
                name: "Filler words only", notes: "The app's built-in light edit.", provider: .claudeCode,
                model: AnthropicClient.defaultModel, effort: .low, instructions: PolishPrompt.fillerWordsTemplate,
                updatedAt: now),
            PolishConfiguration(
                name: "Full polish", notes: "The app's built-in copy edit.", provider: .claudeCode,
                model: AnthropicClient.defaultModel, effort: .low, instructions: PolishPrompt.fullTemplate,
                updatedAt: now),
        ]
    }
}

/// Everything the Lab keeps on disk.
public struct PolishLabState: Codable, Sendable, Equatable {
    public var configurations: [PolishConfiguration]
    /// Which configuration polishes each style's dictations, by `WritingStyle.rawValue`. A
    /// style that isn't here follows Settings.
    public var assignments: [String: UUID]

    public init(configurations: [PolishConfiguration] = [], assignments: [String: UUID] = [:]) {
        self.configurations = configurations
        self.assignments = assignments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configurations = try container.decodeIfPresent([PolishConfiguration].self, forKey: .configurations) ?? []
        assignments = try container.decodeIfPresent([String: UUID].self, forKey: .assignments) ?? [:]
    }
}

/// The Lab's configurations, persisted as JSON, and which styles each one is used for.
@MainActor
@Observable
public final class PolishLabStore {
    public private(set) var configurations: [PolishConfiguration] = []
    private var assignments: [String: UUID] = [:]
    private let fileURL: URL?

    /// Loads the saved Lab, or starts one with the built-in prompts.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let state = Self.load(from: fileURL) {
            configurations = state.configurations
            assignments = state.assignments
        } else {
            configurations = PolishConfiguration.starters()
            save()
        }
        dropDanglingAssignments()
    }

    /// In-memory only, for previews, snapshots and tests.
    public init(preview state: PolishLabState) {
        fileURL = nil
        configurations = state.configurations
        assignments = state.assignments
    }

    public func configuration(id: UUID) -> PolishConfiguration? {
        configurations.first { $0.id == id }
    }

    /// The configuration that polishes this style's dictations, or `nil` to follow Settings.
    public func configuration(for style: WritingStyle) -> PolishConfiguration? {
        assignments[style.rawValue].flatMap(configuration(id:))
    }

    /// The styles this configuration is used for.
    public func styles(for id: UUID) -> Set<WritingStyle> {
        Set(WritingStyle.allCases.filter { assignments[$0.rawValue] == id })
    }

    /// Whether any style uses Lab configurations at all.
    public var hasAssignments: Bool { !assignments.isEmpty }

    /// Styles that use a Lab configuration, in the usual order.
    public var assignedStyles: [WritingStyle] {
        WritingStyle.allCases.filter { configuration(for: $0) != nil }
    }

    @discardableResult
    public func add(_ configuration: PolishConfiguration) -> PolishConfiguration {
        configurations.append(configuration)
        save()
        return configuration
    }

    /// A new configuration at the end, with a name no other one has.
    @discardableResult
    public func addUntitled() -> PolishConfiguration {
        add(.untitled(named: Self.uniqueName("Untitled", existing: Set(configurations.map(\.name)))))
    }

    public func update(_ configuration: PolishConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        var updated = configuration
        updated.updatedAt = Date()
        configurations[index] = updated
        save()
    }

    /// A copy right after the original, named "… copy", used for no styles yet.
    @discardableResult
    public func duplicate(id: UUID) -> PolishConfiguration? {
        guard let original = configuration(id: id) else { return nil }
        return duplicate(original)
    }

    /// Saves this version as a new configuration right after the one it came from (or at the
    /// end), named "… copy", used for no styles yet. The original is left as it was.
    @discardableResult
    public func duplicate(_ version: PolishConfiguration) -> PolishConfiguration {
        var copy = version
        copy.id = UUID()
        copy.name = Self.copyName(for: version.name, existing: Set(configurations.map(\.name)))
        copy.updatedAt = Date()
        if let index = configurations.firstIndex(where: { $0.id == version.id }) {
            configurations.insert(copy, at: index + 1)
        } else {
            configurations.append(copy)
        }
        save()
        return copy
    }

    /// Deletes it; the styles it was used for go back to following Settings.
    public func delete(id: UUID) {
        configurations.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
        save()
    }

    /// Uses this configuration for exactly these styles, taking them over from whichever
    /// configuration had them. Its other styles go back to following Settings.
    public func setStyles(_ styles: Set<WritingStyle>, for id: UUID) {
        guard configuration(id: id) != nil else { return }
        for style in WritingStyle.allCases {
            if styles.contains(style) {
                assignments[style.rawValue] = id
            } else if assignments[style.rawValue] == id {
                assignments[style.rawValue] = nil
            }
        }
        save()
    }

    /// Every style back to following Settings.
    public func clearAssignments() {
        assignments = [:]
        save()
    }

    // MARK: - Persistence

    public var state: PolishLabState { PolishLabState(configurations: configurations, assignments: assignments) }

    private func dropDanglingAssignments() {
        let ids = Set(configurations.map(\.id))
        let kept = assignments.filter { ids.contains($0.value) && WritingStyle(rawValue: $0.key) != nil }
        if kept != assignments {
            assignments = kept
            save()
        }
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// `nil` when there's nothing saved yet. A file that won't decode is copied aside first,
    /// so starting fresh can never overwrite prompts someone spent an afternoon tuning.
    private static func load(from url: URL) -> PolishLabState? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url), !data.isEmpty
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PolishLabState.self, from: data) else {
            _ = HistoryStore.quarantine(url)
            return nil
        }
        return state
    }

    static func copyName(for name: String, existing: Set<String>) -> String {
        uniqueName("\(name) copy", existing: existing)
    }

    /// `base`, or `base 2`, `base 3`… whichever is free.
    static func uniqueName(_ base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}

// MARK: - Word diff

/// What changed between a transcript and its polished version, word by word, for reading a
/// Lab result at a glance: struck-through words were removed, highlighted ones added.
public enum WordDiff {
    public enum Segment: Equatable, Sendable {
        case same(String)
        case removed(String)
        case added(String)
    }

    /// Words are compared ignoring case and surrounding punctuation, so "like," and "Like" are
    /// the same word; the revised spelling is what's shown for words both versions share.
    /// Neighbouring segments of the same kind are merged. Line breaks in the revised text are
    /// kept on the end of the word before them, so a polished email keeps its paragraphs.
    public static func diff(original: String, revised: String) -> [Segment] {
        let before = tokens(original)
        let after = tokensWithBreaks(revised).map { $0.word + $0.breaks }
        let a = before.map(normalized)
        let b = after.map(normalized)

        // Longest common subsequence, filled from the end so the walk below goes forwards.
        let n = a.count, m = b.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var segments: [Segment] = []
        func join(_ x: String, _ y: String) -> String {
            x.last?.isNewline == true ? x + y : x + " " + y
        }
        func push(_ segment: Segment) {
            if let last = segments.last {
                switch (last, segment) {
                case (.same(let x), .same(let y)): segments[segments.count - 1] = .same(join(x, y)); return
                case (.removed(let x), .removed(let y)): segments[segments.count - 1] = .removed(join(x, y)); return
                case (.added(let x), .added(let y)): segments[segments.count - 1] = .added(join(x, y)); return
                default: break
                }
            }
            segments.append(segment)
        }

        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                push(.same(after[j]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                push(.removed(before[i]))
                i += 1
            } else {
                push(.added(after[j]))
                j += 1
            }
        }
        while i < n { push(.removed(before[i])); i += 1 }
        while j < m { push(.added(after[j])); j += 1 }
        return segments
    }

    /// Words removed and added, counted.
    public static func counts(original: String, revised: String) -> (removed: Int, added: Int) {
        diff(original: original, revised: revised).reduce(into: (0, 0)) { total, segment in
            switch segment {
            case .removed(let text): total.0 += tokens(text).count
            case .added(let text): total.1 += tokens(text).count
            case .same: break
            }
        }
    }

    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// Each word with the line breaks in the gap after it ("" when the gap has none). Breaks
    /// after the last word are dropped.
    static func tokensWithBreaks(_ text: String) -> [(word: String, breaks: String)] {
        var result: [(word: String, breaks: String)] = []
        var word = ""
        for character in text {
            if character.isWhitespace || character.isNewline {
                if !word.isEmpty {
                    result.append((word, ""))
                    word = ""
                }
                if character.isNewline, !result.isEmpty { result[result.count - 1].breaks.append(character) }
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty {
            result.append((word, ""))
        } else if !result.isEmpty {
            result[result.count - 1].breaks = ""
        }
        return result
    }

    static func normalized(_ token: String) -> String {
        let straight = token.trimmingCharacters(in: .newlines)
            .replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
        let trimmed = straight.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        return trimmed.isEmpty ? straight : trimmed
    }
}

// MARK: - Lab page helpers

/// Moving through the Lab's configuration list from the keyboard, like a Mail list: ↑ and ↓
/// stop at the ends rather than wrapping.
public enum PolishLabNavigation {
    /// The id `step` rows from `current` in `order`, clamped to the ends. With nothing (or
    /// something no longer listed) selected, ↓ starts at the top and ↑ at the bottom. `nil`
    /// when there's nowhere to go: an empty list, no step, or already at that end.
    public static func neighbor<ID: Equatable>(of current: ID?, step: Int, in order: [ID]) -> ID? {
        guard !order.isEmpty, step != 0 else { return nil }
        guard let current, let index = order.firstIndex(of: current) else {
            return step > 0 ? order.first : order.last
        }
        let target = order[min(max(index + step, 0), order.count - 1)]
        return target == current ? nil : target
    }
}

/// How the Lab lays out its results: runs on the same text, in the same style and app, sit
/// together under one header naming the text, so a Run All batch reads as one comparison and
/// older runs on other text don't look like they belong to it.
public enum PolishLabResults {
    /// Neighbouring items with equal keys, in their original order. Items with the same key
    /// that aren't next to each other stay in separate groups, so time order is kept.
    public static func consecutiveGroups<Item, Key: Equatable>(
        _ items: [Item], by key: (Item) -> Key
    ) -> [[Item]] {
        var groups: [[Item]] = []
        var lastKey: Key?
        for item in items {
            let itemKey = key(item)
            if let lastKey, lastKey == itemKey, !groups.isEmpty {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
            lastKey = itemKey
        }
        return groups
    }

    /// The text on one line: whitespace and line breaks collapsed, cut to `maxWords` words
    /// with an ellipsis when there were more.
    public static func excerpt(_ text: String, maxWords: Int) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let kept = words.prefix(max(maxWords, 0)).joined(separator: " ")
        return words.count > maxWords ? kept + "…" : kept
    }
}
