import AppKit
import Foundation
import MurmurDictionary
import MurmurKit
import Observation

// CONTRACT — owned by the core agent. The public surface below is what the HUD, the main
// window and the menu bar read; keep it stable. Bodies are placeholders until the real
// state machine lands.

/// The dictation state machine: hotkey → record → transcribe → polish → insert → history.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        /// Microphone open, capturing.
        case listening
        /// Key released; the speech engine is running.
        case transcribing
        /// AI polish is rewriting the transcript.
        case polishing
        /// Text was inserted (or copied). Shown briefly, then back to idle.
        case done
        /// The user pressed Esc. Shown briefly, then back to idle.
        case cancelled
        /// Shown briefly with a short message, then back to idle.
        case failed(String)

        var isRecording: Bool { self == .listening }
        var isBusy: Bool { self == .transcribing || self == .polishing }
    }

    /// Number of samples kept in `levels`.
    static let levelHistoryCount = 48

    private(set) var phase: Phase = .idle
    /// Recording continues without holding the key; tap it again (or press Stop) to finish.
    private(set) var isHandsFree = false
    /// Smoothed microphone level, 0…1. Updated ~30×/s while listening.
    private(set) var level: Float = 0
    /// Recent levels, oldest first, for the waveform. Always `levelHistoryCount` long.
    private(set) var levels: [Float] = Array(repeating: 0, count: DictationController.levelHistoryCount)
    /// When the current recording started.
    private(set) var recordingStartedAt: Date?
    /// The app that had focus when recording started.
    private(set) var context: AppContext?
    /// The most recent finished dictation.
    private(set) var lastRecord: HistoryRecord?
    /// Whether the global hotkey is armed (false usually means Accessibility is missing).
    private(set) var isHotkeyActive = false

    let settings: Settings
    let history: HistoryStore
    let snippets: SnippetStore
    let dictionary: DictionaryStore
    let models: ModelManager

    init(
        settings: Settings,
        history: HistoryStore,
        snippets: SnippetStore,
        dictionary: DictionaryStore,
        models: ModelManager
    ) {
        self.settings = settings
        self.history = history
        self.snippets = snippets
        self.dictionary = dictionary
        self.models = models
    }

    // MARK: - Lifecycle

    /// Arms the hotkeys. Returns `false` when the event tap couldn't be created.
    @discardableResult
    func activate() -> Bool { false }

    func deactivate() {}

    /// Re-reads shortcut settings (push-to-talk key, paste-last) and re-arms.
    func reloadShortcuts() {}

    // MARK: - Recording

    /// Start (hands-free) from a button, or stop if already recording.
    func toggleRecording() {}

    func startRecording(handsFree: Bool) {}

    /// Finish the recording and process it.
    func stopRecording() {}

    /// Discard the recording without inserting anything.
    func cancel() {}

    // MARK: - History actions

    /// Pastes the most recent dictation into the focused app again.
    func pasteLast() {}

    /// Types a history item into the focused app.
    func insert(_ record: HistoryRecord) {}

    /// Re-runs speech recognition (and the text pipeline) on a record's saved audio.
    func retry(_ record: HistoryRecord) async {}
}
