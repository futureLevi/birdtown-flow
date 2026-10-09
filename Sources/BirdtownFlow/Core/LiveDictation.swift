import Foundation
import MurmurKit

/// The work one recording does while it's still going: long recordings are cut into windows
/// that are saved, then decoded, before the key comes up. One per dictation session.
///
/// Rule 2 holds window by window: a window's audio is appended to the record's WAV and the
/// (hidden) placeholder History row exists before that window is decoded.
///
/// Not built yet: every method is a no-op, so dictations take today's path.
@MainActor
final class LiveDictation {
    /// Raw joined text of committed windows, after each commit. `ProgressivePolisher` subscribes.
    var onCommittedText: (@MainActor (String) -> Void)?
    /// The windowed transcription in progress. `nil` until the recording is long enough.
    private(set) var transcriber: SegmentedTranscriber?

    private let id: UUID
    private let generation: Int
    private let recorder: AudioRecorder
    private let models: ModelManager
    private let history: HistoryStore
    private let settings: Settings
    private let vocabulary: @MainActor () -> [String]
    private let placeholder: @MainActor () async -> HistoryRecord

    /// - Parameters:
    ///   - id: the History record this recording becomes.
    ///   - generation: the recorder generation whose samples belong to this recording.
    ///   - vocabulary: the dictionary terms to boost, read when the first window is cut.
    ///   - placeholder: the record to save, hidden, before the first window is decoded.
    init(
        id: UUID, generation: Int, recorder: AudioRecorder, models: ModelManager,
        history: HistoryStore, settings: Settings, vocabulary: @escaping @MainActor () -> [String],
        placeholder: @escaping @MainActor () async -> HistoryRecord
    ) {
        self.id = id
        self.generation = generation
        self.recorder = recorder
        self.models = models
        self.history = history
        self.settings = settings
        self.vocabulary = vocabulary
        self.placeholder = placeholder
    }

    /// Recording started.
    func start() {}

    /// Key-up: stops cutting windows and closes the WAV writer. A window already being
    /// decoded keeps going; `LongTranscription` waits for it.
    func stop() async {}

    /// Esc, a discarded or dropped recording: cancels the work and deletes the placeholder row
    /// and its WAV, so nothing is left behind.
    func cancel() {}

    /// `DictationController.process` took over the row: it's no longer hidden.
    func handOff() {}
}
