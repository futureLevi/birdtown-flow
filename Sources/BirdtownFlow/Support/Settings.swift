import Foundation
import MurmurKit
import Observation

/// Which speech model transcribes an utterance.
enum SpeechEngineChoice: String, CaseIterable, Identifiable, Sendable {
    /// Parakeet TDT v3 post-trained by moondream. FluidAudio's recommended default: more
    /// accurate than v3 on every benchmark at the same speed. 25 languages.
    case parakeetUltra
    /// The original Parakeet TDT v3. Same languages, slightly less accurate than Ultra.
    case parakeetV3
    /// Parakeet TDT v2. English only.
    case parakeetV2
    /// Apple's built-in SpeechTranscriber. No download.
    case apple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeetUltra: "Parakeet Ultra"
        case .parakeetV3: "Parakeet v3"
        case .parakeetV2: "Parakeet v2 (English)"
        case .apple: "Apple Speech"
        }
    }

    var detail: String {
        switch self {
        case .parakeetUltra: "Most accurate. 25 languages. Runs on the Neural Engine."
        case .parakeetV3: "The original multilingual Parakeet."
        case .parakeetV2: "English-only Parakeet."
        case .apple: "Built into macOS. Nothing to download."
        }
    }

    /// Approximate one-time download, for the UI.
    var downloadSize: String {
        switch self {
        case .parakeetUltra: "≈ 620 MB"
        case .parakeetV3: "≈ 480 MB"
        case .parakeetV2: "≈ 480 MB"
        case .apple: "Managed by macOS"
        }
    }

    var isParakeet: Bool { self != .apple }
}

/// How to start a recording that keeps going without holding a key.
enum HandsFreeShortcut: String, CaseIterable, Identifiable, Sendable {
    /// Double-tap the push-to-talk key, or press Space while holding it.
    case doubleTap
    /// A shortcut of its own: a tap of Control and Option together, or the chord recorded in
    /// `Settings.handsFreeChord`. Press it again to finish. For a 🌐 key that macOS also
    /// answers (a quick tap opens the emoji picker), or to match Wispr Flow.
    ///
    /// The name and saved value predate recorded chords and are kept so saved choices load.
    case controlOption
    case off

    var id: String { rawValue }

    /// `keyName` is the push-to-talk key as the UI spells it (`SetupKit.name(for:)`), so the
    /// hands-free picker names the key the same way as the push-to-talk picker above it.
    func title(keyName: String) -> String {
        title(keyName: keyName, chord: nil)
    }

    /// `chord` is the recorded hands-free chord, which `.controlOption` uses instead of ⌃⌥.
    func title(keyName: String, chord: KeyChord?) -> String {
        switch self {
        case .doubleTap: "Double-tap \(keyName)"
        case .controlOption: chord?.displayName ?? "Control + Option"
        case .off: "Off"
        }
    }
}

/// Light, dark, or whatever macOS is set to.
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Every user preference. One observable object so SwiftUI views bind straight to it.
///
/// Add new preferences here — never read `UserDefaults` directly elsewhere.
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    // MARK: Shortcuts

    /// Hold to talk: one of the quick picks, or any modifier key or chord from the recorder.
    var pushToTalkKey: PushToTalkKey {
        didSet { defaults.set(pushToTalkKey.storageValue, forKey: Keys.pushToTalkKey) }
    }
    /// Starts a recording that keeps going without holding the key, until the same gesture
    /// (or a tap of the key) finishes it.
    var handsFreeShortcut: HandsFreeShortcut {
        didSet { defaults.set(handsFreeShortcut.rawValue, forKey: Keys.handsFreeShortcut) }
    }
    var handsFreeEnabled: Bool { handsFreeShortcut != .off }
    /// The recorded hands-free chord (⌃⇧Space…), used when `handsFreeShortcut` is
    /// `.controlOption`. `nil` means a tap of ⌃⌥. Kept while another hands-free option is
    /// chosen, so switching back is one click.
    var handsFreeChord: KeyChord? {
        didSet { defaults.set(handsFreeChord?.storageValue, forKey: Keys.handsFreeChord) }
    }
    /// What `HotkeyMonitor.handsFreeChord` should be: the recorded chord while hands-free uses
    /// its own shortcut, else `nil`.
    var activeHandsFreeChord: KeyChord? {
        handsFreeShortcut == .controlOption ? handsFreeChord : nil
    }
    /// Pastes the most recent dictation again.
    var pasteLastShortcutEnabled: Bool {
        didSet { defaults.set(pasteLastShortcutEnabled, forKey: Keys.pasteLastShortcutEnabled) }
    }
    /// The paste-last chord, ⌃⌥V unless the user recorded another.
    var pasteLastShortcut: KeyChord {
        didSet { defaults.set(pasteLastShortcut.storageValue, forKey: Keys.pasteLastShortcut) }
    }

    /// The shortcuts each action has, for `ShortcutRules.check(_:for:inUse:)`. A saved chord
    /// counts even while its action is off or set to another gesture, since switching back
    /// is one click and would otherwise bring back a clash. The ⌃⌥ tap and double-tap aren't
    /// chords, so they can't collide and aren't listed.
    var shortcutsInUse: [ShortcutRole: KeyShortcut] {
        var inUse: [ShortcutRole: KeyShortcut] = [
            .pushToTalk: pushToTalkKey,
            .pasteLast: .keys(pasteLastShortcut),
        ]
        if let handsFreeChord { inUse[.handsFree] = .keys(handsFreeChord) }
        return inUse
    }

    // MARK: Feedback

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }
    /// Keep a small resting pill on screen while idle, like Wispr Flow's bar.
    var showIdlePill: Bool {
        didSet { defaults.set(showIdlePill, forKey: Keys.showIdlePill) }
    }
    /// Lower other apps' audio while recording. Off by default.
    var duckAudioWhileRecording: Bool {
        didSet { defaults.set(duckAudioWhileRecording, forKey: Keys.duckAudioWhileRecording) }
    }

    // MARK: Audio & speech

    /// `nil` follows the system default input.
    var inputDeviceUID: String? {
        didSet { defaults.set(inputDeviceUID, forKey: Keys.inputDeviceUID) }
    }
    var engine: SpeechEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }
    /// Feed dictionary words to the recognizer (Parakeet CTC boosting / Apple context).
    var vocabularyBoosting: Bool {
        didSet { defaults.set(vocabularyBoosting, forKey: Keys.vocabularyBoosting) }
    }

    // MARK: Text

    var removeFillers: Bool {
        didSet { defaults.set(removeFillers, forKey: Keys.removeFillers) }
    }
    /// "new line", "new paragraph" become line breaks.
    var spokenCommands: Bool {
        didSet { defaults.set(spokenCommands, forKey: Keys.spokenCommands) }
    }
    /// Restore whatever was on the clipboard after pasting a dictation.
    var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard) }
    }

    // MARK: Style

    /// Writing style per app category.
    private(set) var styles: [AppCategory: WritingStyle]

    func style(for category: AppCategory) -> WritingStyle {
        styles[category] ?? WritingStyle.defaultStyle(for: category)
    }

    func setStyle(_ style: WritingStyle, for category: AppCategory) {
        styles[category] = style
        defaults.set(styles.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue },
                     forKey: Keys.styles)
    }

    // MARK: AI polish

    var polishProvider: PolishProvider {
        didSet { defaults.set(polishProvider.rawValue, forKey: Keys.polishProvider) }
    }
    /// How much the AI may change: just the filler, or a full edit.
    var polishLevel: PolishLevel {
        didSet { defaults.set(polishLevel.rawValue, forKey: Keys.polishLevel) }
    }
    var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: Keys.anthropicModel) }
    }
    var openAIBaseURL: String {
        didSet { defaults.set(openAIBaseURL, forKey: Keys.openAIBaseURL) }
    }
    var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: Keys.openAIModel) }
    }
    /// After this long, polish is abandoned and the deterministic text is used.
    var polishTimeout: Double {
        didSet { defaults.set(polishTimeout, forKey: Keys.polishTimeout) }
    }

    // MARK: Appearance

    /// Applied to the whole app (`AppearancePreference.apply()`); the pill is navy either way.
    var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            appearance.apply()
        }
    }

    // MARK: History

    /// Days of text history to keep. `0` keeps forever.
    var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays) }
    }
    /// Days of audio to keep. `0` keeps none; `-1` keeps forever.
    var audioRetentionDays: Int {
        didSet { defaults.set(audioRetentionDays, forKey: Keys.audioRetentionDays) }
    }

    // MARK: Lifecycle

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: -

    private let defaults: UserDefaults

    private enum Keys {
        static let pushToTalkKey = "pushToTalkKey"
        /// Before the shortcut could be chosen: hands-free on (double-tap) or off.
        static let handsFreeEnabled = "handsFreeEnabled"
        static let handsFreeShortcut = "handsFreeShortcut"
        static let handsFreeChord = "handsFreeChord"
        static let pasteLastShortcutEnabled = "pasteLastShortcutEnabled"
        static let pasteLastShortcut = "pasteLastShortcut"
        static let soundEnabled = "soundEnabled"
        static let showIdlePill = "showIdlePill"
        static let duckAudioWhileRecording = "duckAudioWhileRecording"
        static let inputDeviceUID = "inputDeviceUID"
        static let engine = "engine"
        static let vocabularyBoosting = "vocabularyBoosting"
        static let removeFillers = "removeFillers"
        static let spokenCommands = "spokenCommands"
        static let restoreClipboard = "restoreClipboard"
        static let styles = "styles"
        static let polishProvider = "polishProvider"
        static let polishLevel = "polishLevel"
        static let anthropicModel = "anthropicModel"
        static let openAIBaseURL = "openAIBaseURL"
        static let openAIModel = "openAIModel"
        static let polishTimeout = "polishTimeout"
        static let historyRetentionDays = "historyRetentionDays"
        static let audioRetentionDays = "audioRetentionDays"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let appearance = "appearance"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Saved values from before recorded shortcuts ("fn", "rightOption"…) load unchanged.
        pushToTalkKey = PushToTalkKey(storageValue: defaults.string(forKey: Keys.pushToTalkKey) ?? "") ?? .fn
        if let saved = HandsFreeShortcut(rawValue: defaults.string(forKey: Keys.handsFreeShortcut) ?? "") {
            handsFreeShortcut = saved
        } else {
            let wasOn = defaults.object(forKey: Keys.handsFreeEnabled) as? Bool ?? true
            handsFreeShortcut = wasOn ? .doubleTap : .off
        }
        handsFreeChord = KeyChord(storageValue: defaults.string(forKey: Keys.handsFreeChord) ?? "")
        pasteLastShortcutEnabled = defaults.object(forKey: Keys.pasteLastShortcutEnabled) as? Bool ?? true
        pasteLastShortcut = KeyChord(storageValue: defaults.string(forKey: Keys.pasteLastShortcut) ?? "") ?? .pasteLastDefault
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        showIdlePill = defaults.object(forKey: Keys.showIdlePill) as? Bool ?? true
        duckAudioWhileRecording = defaults.object(forKey: Keys.duckAudioWhileRecording) as? Bool ?? false
        inputDeviceUID = defaults.string(forKey: Keys.inputDeviceUID)
        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .parakeetUltra
        vocabularyBoosting = defaults.object(forKey: Keys.vocabularyBoosting) as? Bool ?? true
        removeFillers = defaults.object(forKey: Keys.removeFillers) as? Bool ?? true
        spokenCommands = defaults.object(forKey: Keys.spokenCommands) as? Bool ?? true
        restoreClipboard = defaults.object(forKey: Keys.restoreClipboard) as? Bool ?? true
        let rawStyles = defaults.dictionary(forKey: Keys.styles) as? [String: String] ?? [:]
        styles = rawStyles.reduce(into: [:]) { result, pair in
            if let category = AppCategory(rawValue: pair.key), let style = WritingStyle(rawValue: pair.value) {
                result[category] = style
            }
        }
        polishProvider = PolishProvider(rawValue: defaults.string(forKey: Keys.polishProvider) ?? "") ?? .off
        polishLevel = PolishLevel(rawValue: defaults.string(forKey: Keys.polishLevel) ?? "") ?? .fillerWords
        anthropicModel = defaults.string(forKey: Keys.anthropicModel) ?? AnthropicClient.defaultModel
        openAIBaseURL = defaults.string(forKey: Keys.openAIBaseURL) ?? "https://api.openai.com/v1"
        openAIModel = defaults.string(forKey: Keys.openAIModel) ?? "gpt-4.1-mini"
        polishTimeout = defaults.object(forKey: Keys.polishTimeout) as? Double ?? 4
        historyRetentionDays = defaults.object(forKey: Keys.historyRetentionDays) as? Int ?? 0
        audioRetentionDays = defaults.object(forKey: Keys.audioRetentionDays) as? Int ?? 7
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
    }
}
