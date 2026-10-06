import Foundation
import MurmurDictionary

// Shared value types. Every layer — pipeline, history, UI — speaks in these, so changing a
// case or a field here is an interface change: update every switch, and keep `Codable`
// backward compatible (new fields optional or defaulted) because history is persisted.

// MARK: - Where the user is dictating

/// The kind of app the text is headed for. Drives the writing style.
public enum AppCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case personal
    case work
    case email
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .personal: "Personal messages"
        case .work: "Work messages"
        case .email: "Email"
        case .other: "Everything else"
        }
    }

    /// Short list of example apps, for the Style screen.
    public var examples: String {
        switch self {
        case .personal: "Messages, WhatsApp, Telegram, Signal"
        case .work: "Slack, Teams, Discord, Linear"
        case .email: "Mail, Gmail, Outlook, Superhuman"
        case .other: "Docs, notes, editors, terminals, everything else"
        }
    }

    /// SF Symbol for the category.
    public var symbol: String {
        switch self {
        case .personal: "message"
        case .work: "number"
        case .email: "envelope"
        case .other: "doc.text"
        }
    }
}

/// How dictated text is shaped for a category. Mirrors Wispr Flow's four styles.
public enum WritingStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case formal
    case casual
    case veryCasual
    case excited

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .formal: "Formal"
        case .casual: "Casual"
        case .veryCasual: "Very casual"
        case .excited: "Excited"
        }
    }

    public var summary: String {
        switch self {
        case .formal: "Capitals and full punctuation."
        case .casual: "Capitals, lighter punctuation."
        case .veryCasual: "all lowercase, barely any punctuation"
        case .excited: "Upbeat, with the odd exclamation mark!"
        }
    }

    /// The default style for each category, matching what most people want out of the box.
    public static func defaultStyle(for category: AppCategory) -> WritingStyle {
        switch category {
        case .personal: .casual
        case .work: .casual
        case .email: .formal
        case .other: .formal
        }
    }
}

/// The app that had focus when recording started.
public struct AppContext: Codable, Hashable, Sendable {
    public var bundleID: String?
    public var appName: String?
    /// Front window title, when readable. Used to spot web apps (Gmail, Slack) in browsers.
    public var windowTitle: String?
    public var category: AppCategory

    public init(bundleID: String?, appName: String?, windowTitle: String? = nil, category: AppCategory) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.category = category
    }
}

// MARK: - Snippets

/// Say the trigger, get the expansion. "my calendly link" → "https://calendly.com/…".
public struct Snippet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var trigger: String
    public var expansion: String
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        trigger: String,
        expansion: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

// MARK: - AI polish

/// Who rewrites the transcript after recognition. `off` means the deterministic pipeline only.
public enum PolishProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case appleIntelligence
    case anthropic
    case openAICompatible

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .appleIntelligence: "Apple Intelligence"
        case .anthropic: "Claude"
        case .openAICompatible: "OpenAI-compatible"
        }
    }

    public var subtitle: String {
        switch self {
        case .off: "Fast, private rules only: fillers, spacing, capitals."
        case .appleIntelligence: "On-device. Private and free, on supported Macs."
        case .anthropic: "Claude Haiku via your Anthropic API key. Best quality."
        case .openAICompatible: "OpenAI, Groq, Ollama, LM Studio — any compatible endpoint."
        }
    }

    public var isCloud: Bool { self == .anthropic || self == .openAICompatible }
}

/// Everything a polisher needs to know about one utterance.
public struct PolishRequest: Sendable, Hashable {
    public var text: String
    public var style: WritingStyle
    public var category: AppCategory
    public var appName: String?
    /// Dictionary words, passed as spelling hints. Keep it short — see `DictionaryCorrector.biasLimit`.
    public var vocabulary: [String]

    public init(text: String, style: WritingStyle, category: AppCategory, appName: String?, vocabulary: [String]) {
        self.text = text
        self.style = style
        self.category = category
        self.appName = appName
        self.vocabulary = vocabulary
    }
}

// MARK: - History

/// How a dictation ended.
public enum DictationOutcome: String, Codable, Sendable {
    /// Typed into the focused app.
    case inserted
    /// No text field to type into — left on the clipboard instead.
    case copied
    /// Silence, or nothing recognized. Nothing was typed.
    case empty
    /// The user pressed Esc.
    case cancelled
    /// Something broke. `errorMessage` says what; the audio is kept so it can be retried.
    case failed
}

/// Millisecond timings for one dictation, measured from key release.
public struct DictationTimings: Codable, Hashable, Sendable {
    public var transcribeMs: Int
    public var polishMs: Int
    public var totalMs: Int

    public init(transcribeMs: Int = 0, polishMs: Int = 0, totalMs: Int = 0) {
        self.transcribeMs = transcribeMs
        self.polishMs = polishMs
        self.totalMs = totalMs
    }
}

/// One dictation, as stored in history.
public struct HistoryRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var context: AppContext?
    public var style: WritingStyle?
    /// Display name of the engine, e.g. "Parakeet Ultra".
    public var engine: String
    /// Exactly what the speech engine returned.
    public var rawText: String
    /// What was typed (or would have been).
    public var finalText: String
    /// Which polisher rewrote the text, if any did.
    public var polishedBy: PolishProvider?
    public var corrections: [AppliedCorrection]
    /// Triggers of snippets that expanded.
    public var snippets: [String]
    /// File name inside the recordings directory. `nil` once retention purges the audio.
    public var audioFileName: String?
    /// Seconds of audio captured.
    public var audioDuration: Double
    public var timings: DictationTimings
    public var outcome: DictationOutcome
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: AppContext? = nil,
        style: WritingStyle? = nil,
        engine: String = "",
        rawText: String = "",
        finalText: String = "",
        polishedBy: PolishProvider? = nil,
        corrections: [AppliedCorrection] = [],
        snippets: [String] = [],
        audioFileName: String? = nil,
        audioDuration: Double = 0,
        timings: DictationTimings = DictationTimings(),
        outcome: DictationOutcome = .inserted,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.context = context
        self.style = style
        self.engine = engine
        self.rawText = rawText
        self.finalText = finalText
        self.polishedBy = polishedBy
        self.corrections = corrections
        self.snippets = snippets
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.timings = timings
        self.outcome = outcome
        self.errorMessage = errorMessage
    }

    /// Words in the final text.
    public var wordCount: Int {
        finalText.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Speaking rate for this dictation, or `nil` when too short to be meaningful.
    public var wordsPerMinute: Int? {
        guard audioDuration >= 2, wordCount > 0 else { return nil }
        return Int((Double(wordCount) / (audioDuration / 60)).rounded())
    }

    /// Whether the dictation produced text the user can reuse.
    public var hasText: Bool {
        !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
