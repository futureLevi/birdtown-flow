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
    /// An address behind the expansion, the way ⌘K links text in a document: the expansion
    /// is what shows, and this is what it opens. `nil` (or empty) types the expansion as is.
    public var link: String?
    /// The words in the expansion that `link` goes behind, when only part of it should be the
    /// link: "my calendar" in "grab a time on my calendar". `nil` (or empty) links all of it.
    public var linkText: String?
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        trigger: String,
        expansion: String,
        link: String? = nil,
        linkText: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.link = link
        self.linkText = linkText
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// The linked part of the expansion as link text, when the snippet has an address to put
    /// behind it. It keeps the expansion's own spelling of `linkText`.
    public var linked: SnippetLink? {
        guard let link, !link.isEmpty, let range = linkedRange else { return nil }
        return SnippetLink(text: String(expansion[range]), url: link)
    }

    /// Where the link goes in the expansion: the first place `linkText` appears, ignoring case,
    /// or all of it when `linkText` is empty or no longer in the expansion. `nil` without a link.
    public var linkedRange: Range<String.Index>? {
        guard let link, !link.isEmpty, !expansion.isEmpty else { return nil }
        return linkText.flatMap { Self.range(of: $0, in: expansion) } ?? expansion.startIndex..<expansion.endIndex
    }

    /// What the pipeline types: the expansion with its linked words in their plain form,
    /// "grab a time on my calendar (https://…)". Without a link, the expansion as is.
    public var typed: String {
        guard let linked, let range = linkedRange else { return expansion }
        return expansion.replacingCharacters(in: range, with: linked.plain)
    }

    /// The first place `words` appear in `expansion`, ignoring case and the spaces around them.
    /// `nil` when they're empty or not there.
    public static func range(of words: String, in expansion: String) -> Range<String.Index>? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        return expansion.range(of: words, options: .caseInsensitive)
    }
}

/// Text that opens an address: what a linked snippet inserts.
///
/// The pipeline and History carry it as `plain`, which is also what a plain-text field gets,
/// so nothing is lost where links can't go. Pasting into an app that takes rich text swaps
/// each `plain` back for `text`, linked (see `LinkedText`).
public struct SnippetLink: Codable, Hashable, Sendable {
    public var text: String
    public var url: String

    public init(text: String, url: String) {
        self.text = text
        self.url = url
    }

    /// "my calendar (https://calendar.app.google/…)".
    public var plain: String { "\(text) (\(url))" }

    /// What someone typed as a link, made into an address: "calendly.com/levi" gains
    /// "https://". `nil` when it can't be one: empty, has spaces, or isn't a URL, domain
    /// or email address.
    public static func normalizedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("mailto:") || lowered.hasPrefix("tel:") { return trimmed }
        if let scheme = lowered.range(of: "://") {
            // A scheme and something after it: "https://x", not "://x" or "https://".
            return scheme.lowerBound > lowered.startIndex && scheme.upperBound < lowered.endIndex ? trimmed : nil
        }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        if parts.count == 2 {
            // "me@example.com" mails; "@handle" and "me@" aren't addresses.
            guard !parts[0].isEmpty, Token.isLinkLike(String(parts[1])) else { return nil }
            return "mailto:" + trimmed
        }
        guard parts.count == 1, Token.isLinkLike(trimmed) else { return nil }
        return "https://" + trimmed
    }
}

// MARK: - AI polish

/// Who rewrites the transcript after recognition. `off` means the deterministic pipeline only.
public enum PolishProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case appleIntelligence
    case anthropic
    case openAICompatible
    /// Claude through Claude Code signed in on this Mac, on the person's own Claude plan.
    /// Personal builds only: Anthropic's terms don't let an app run its users' requests on
    /// their Pro or Max logins, so this must come out before Birdtown Flow is sold.
    case claudeCode

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .appleIntelligence: "Apple Intelligence"
        case .anthropic: "Claude"
        case .openAICompatible: "OpenAI-compatible"
        case .claudeCode: "Claude Code"
        }
    }

    public var subtitle: String {
        switch self {
        case .off: "Fast, private rules only: fillers, spacing, capitals."
        case .appleIntelligence: "On-device. Private and free, on supported Macs."
        case .anthropic: "Claude Haiku 5.5 via your Anthropic API key. Best quality."
        case .openAICompatible: "OpenAI, Groq, Ollama, LM Studio, or any compatible endpoint."
        case .claudeCode: "Your Claude plan, through Claude Code on this Mac. For personal testing."
        }
    }

    /// Needs an API key of its own.
    public var isCloud: Bool { self == .anthropic || self == .openAICompatible }
    /// The text leaves this Mac.
    public var sendsText: Bool { isCloud || self == .claudeCode }
}

/// How much the AI is allowed to change.
public enum PolishLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Take out "um", "like", "you know" and stutters; leave every other word as spoken.
    case fillerWords
    /// Also fix punctuation and grammar, apply self-corrections ("Friday, no wait, Monday"),
    /// write numbers and dictated lists properly, and follow the app's style.
    case full

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fillerWords: "Filler words only"
        case .full: "Full polish"
        }
    }

    public var detail: String {
        switch self {
        case .fillerWords: "Takes out “um”, “like”, “you know” and stutters. Every other word stays as you said it."
        case .full: "Also fixes punctuation and grammar, applies your corrections (“Friday, no wait, Monday”) and formats lists."
        }
    }
}

/// Everything a polisher needs to know about one utterance.
public struct PolishRequest: Sendable, Hashable {
    public var text: String
    public var style: WritingStyle
    public var category: AppCategory
    public var appName: String?
    /// Dictionary words, passed as spelling hints. Keep it short — see `DictionaryCorrector.biasLimit`.
    public var vocabulary: [String]
    public var level: PolishLevel
    /// A system prompt to use instead of the built-in one: a Lab configuration's.
    public var instructions: String?
    /// One part of a long dictation (`PolishChunker`): the end of the part before it, as
    /// dictated. The model reads it for sense and leaves it out of its reply.
    public var context: String?
    /// One part of a long dictation, and not the last: the text goes on after it.
    public var continues: Bool

    public init(
        text: String, style: WritingStyle, category: AppCategory, appName: String?, vocabulary: [String],
        level: PolishLevel = .full, instructions: String? = nil, context: String? = nil, continues: Bool = false
    ) {
        self.text = text
        self.style = style
        self.category = category
        self.appName = appName
        self.vocabulary = vocabulary
        self.level = level
        self.instructions = instructions
        self.context = context
        self.continues = continues
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
    /// `true` when windows of a long dictation were decoded while it was recorded:
    /// `transcribeMs` is then only what was left at key-up (the window being decoded and the
    /// last few seconds), not the engine's time on the whole recording. `nil` otherwise (a
    /// key that came up before the first window was cut left key-up all of it), and in
    /// records saved before it existed, so their JSON reads as it always did.
    public var transcribedWhileRecording: Bool?
    /// Claude Code: the model's own share of `polishMs` (`PolishDiagnostics.modelMs`).
    public var polishModelMs: Int?
    /// Claude Code: no session was waiting, so polish also waited for Claude Code to start.
    public var polishStartedCold: Bool?
    /// The model and effort polish went out with, e.g. `AnthropicClient.defaultModel` and "low".
    public var polishModel: String?
    public var polishEffort: String?
    /// From the key going down to the microphone's first audio. Not part of `totalMs`, which
    /// starts at key-up.
    public var micLiveMs: Int?

    // Every field after `totalMs` is optional and left out of the JSON when `nil`, so records
    // saved before it existed read as they always did.
    public init(
        transcribeMs: Int = 0, polishMs: Int = 0, totalMs: Int = 0, transcribedWhileRecording: Bool? = nil,
        polishModelMs: Int? = nil, polishStartedCold: Bool? = nil, polishModel: String? = nil,
        polishEffort: String? = nil, micLiveMs: Int? = nil
    ) {
        self.transcribeMs = transcribeMs
        self.polishMs = polishMs
        self.totalMs = totalMs
        self.transcribedWhileRecording = transcribedWhileRecording
        self.polishModelMs = polishModelMs
        self.polishStartedCold = polishStartedCold
        self.polishModel = polishModel
        self.polishEffort = polishEffort
        self.micLiveMs = micLiveMs
    }

    /// Whether anything was measured. Failed and cancelled dictations can have no timings.
    public var isEmpty: Bool { transcribeMs == 0 && polishMs == 0 && totalMs == 0 }

    /// Time outside transcription and polish: handing the audio over, cleanup, the dictionary
    /// and typing the text. Never negative, even if the parts were rounded past the total.
    public var otherMs: Int { max(0, totalMs - transcribeMs - polishMs) }

    /// How many times faster than real time the engine transcribed `audioSeconds` of speech
    /// (40 means a minute of audio took 1.5 s), or `nil` when either side wasn't measured.
    /// Also `nil` when it was `transcribedWhileRecording`: `transcribeMs` covers only the
    /// last few seconds, so six minutes over 600 ms would claim 600× for a 40× engine.
    public func realtimeFactor(audioSeconds: Double) -> Double? {
        guard audioSeconds > 0, transcribeMs > 0, transcribedWhileRecording != true else { return nil }
        return audioSeconds * 1000 / Double(transcribeMs)
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
    /// The Lab configuration it used, by name, when one polished this style.
    public var polishConfiguration: String?
    public var corrections: [AppliedCorrection]
    /// Triggers of snippets that expanded.
    public var snippets: [String]
    /// Linked snippets in `finalText`, which holds each one's plain form. `nil` when none.
    public var links: [SnippetLink]?
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
        links: [SnippetLink]? = nil,
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
        self.links = links
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.timings = timings
        self.outcome = outcome
        self.errorMessage = errorMessage
    }

    /// Words in the final text: runs of characters that aren't whitespace or newlines.
    ///
    /// Counted in place rather than with `split`, which allocated an array of substrings per
    /// call; Home sums this over the whole history. Same characters, same answer.
    public var wordCount: Int {
        var count = 0
        var inWord = false
        for character in finalText {
            if character.isWhitespace || character.isNewline {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    /// Speaking rate for this dictation, or `nil` when too short to be meaningful.
    public var wordsPerMinute: Int? {
        guard audioDuration >= 2 else { return nil }
        let words = wordCount
        guard words > 0 else { return nil }
        return Int((Double(words) / (audioDuration / 60)).rounded())
    }

    /// Whether the dictation produced text the user can reuse.
    ///
    /// The same test as trimming whitespace and newlines and checking for anything left, without
    /// building the trimmed copy.
    public var hasText: Bool {
        let blank = CharacterSet.whitespacesAndNewlines
        return finalText.unicodeScalars.contains { !blank.contains($0) }
    }
}
