import Foundation
import MurmurKit

/// The work one recording does while it's still going: long recordings are cut into windows
/// that are saved, then decoded, before the key comes up. One per dictation session.
///
/// Rule 2 holds window by window: a window's audio is appended to the record's WAV and the
/// (hidden) placeholder History row exists before that window is decoded.
///
/// Nothing happens for the first 20 s, so a short dictation never gets this far. After that,
/// once a second, the next window is cut when the audio allows and the last one is decoded.
@MainActor
final class LiveDictation {
    /// Raw joined text of committed windows, after each commit. `ProgressivePolisher` subscribes.
    var onCommittedText: (@MainActor (String) -> Void)?
    /// The windowed transcription in progress. `nil` until the recording is long enough.
    private(set) var transcriber: SegmentedTranscriber?

    /// Samples captured before windows start being cut (20 s).
    static let armingSamples = 320_000
    private static let tick: Duration = .seconds(1)
    private static let sampleRate = 16_000.0

    private let id: UUID
    private let generation: Int
    private let recorder: AudioRecorder
    private let models: ModelManager
    private let history: HistoryStore
    private let settings: Settings
    private let vocabulary: @MainActor () -> [String]
    private let placeholder: @MainActor () async -> HistoryRecord

    private var loop: Task<Void, Never>?
    private var writer: IncrementalWAVWriter?
    /// Windows already passed to `onCommittedText`.
    private var reportedWindows = 0
    /// The placeholder row is in History.
    private var isSaved = false
    /// `stop` or `cancel` ran: no more windows, appends or rows.
    private var isEnded = false
    private var isCancelled = false
    /// The dictation owns the row and the WAV now.
    private var isHandedOff = false

    /// - Parameters:
    ///   - id: the History record this recording becomes.
    ///   - generation: the recorder generation whose samples belong to this recording.
    ///   - vocabulary: the dictionary terms to boost, read when windows start.
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
    func start() {
        guard loop == nil, !isEnded else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard let self, !Task.isCancelled, !self.isEnded else { return }
                guard await self.step() else { return }
            }
        }
    }

    /// Key-up: stops cutting windows and closes the WAV writer. A window already being
    /// decoded keeps going; `LongTranscription` waits for it.
    ///
    /// Doesn't wait for a tick in progress: it may be waiting for a copy of the audio, queued
    /// behind the recorder stopping its device (slow on Bluetooth), which key-up never waits
    /// for. Every step of a tick checks `isEnded` first, so it saves nothing more. Closing
    /// the writer is the part that must finish: an append already running ends first and
    /// none can start after, so the whole WAV `process` writes next is never overwritten.
    func stop() async {
        guard !isEnded else { return }
        isEnded = true
        loop?.cancel()
        loop = nil
        await writer?.close()
    }

    /// Esc, a discarded or dropped recording: cancels the work and deletes the placeholder row
    /// and its WAV, so nothing is left behind.
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        isEnded = true
        loop?.cancel()
        loop = nil
        if let transcriber {
            Task { await transcriber.cancelWork() }
            Log.timing.info("live cancelled")
        }
        // Once handed off, the row and the WAV are the dictation's (with its Retry).
        guard !isHandedOff else { return }
        if let writer {
            Task { await writer.discard() }
        }
        // Also removes the WAV and the in-progress mark.
        if isSaved { history.delete(ids: [id]) }
    }

    /// `DictationController.process` took over the row: it's no longer hidden.
    func handOff() {
        isHandedOff = true
        history.clearInProgress(id)
        // The row was saved without audio: the whole WAV couldn't be written over the partial
        // one, which nothing would point at any more.
        if let writer, history.record(id: id)?.audioFileName == nil {
            Task { await writer.discard() }
        }
    }

    // MARK: - Ticks

    /// Returns `false` when there's nothing more to do for this recording.
    private func step() async -> Bool {
        guard let transcriber else { return await arm() }
        // Windows given up (one failed, or its audio couldn't be saved) won't be used, so
        // neither would anything more: stop, rather than copy the recording every second.
        guard await transcriber.isAcceptingWindows, !isEnded else { return false }

        // Text decoded since the last tick.
        let decoded = await transcriber.committedCount
        if decoded > reportedWindows {
            reportedWindows = decoded
            let text = await transcriber.committedRawText
            guard !isEnded else { return false }
            onCommittedText?(text)
        }

        // One window at a time: the next is cut once the last is decoded.
        guard !isEnded, !(await transcriber.isBusy) else { return !isEnded }
        let start = await transcriber.analysisStart
        guard let captured = await recorder.capturedAudio(from: start, generation: generation) else { return false }
        let offset = captured.end - captured.samples.count
        guard !isEnded, let planned = await transcriber.advance(audio: captured.samples, offset: offset) else {
            return !isEnded
        }
        guard !isEnded else { return false }

        // Rule 2: the window's audio is on disk, and its row exists, before it's decoded.
        let writer = self.writer ?? IncrementalWAVWriter(url: history.newRecordingURL(for: id))
        self.writer = writer
        do {
            try await writer.append(captured.samples, from: offset, upTo: planned.window.audio.upperBound)
        } catch {
            // `cancel` closed the writer meanwhile.
            guard !isEnded else { return false }
            Log.audio.error("couldn't save a recording in progress: \(error.localizedDescription, privacy: .public)")
            await transcriber.disable("wavWriteFailed")
            return false
        }
        guard !isEnded else { return false }
        if !isSaved {
            var record = await placeholder()
            guard !isEnded else { return false }
            record.audioFileName = writer.url.lastPathComponent
            history.markInProgress(id)
            history.add(record)
            isSaved = true
        }
        await transcriber.run(planned)
        return true
    }

    /// Before the first window: waits for 20 s of audio and a loaded engine that can decode
    /// windows. Returns `false` when windows won't start for this recording.
    private func arm() async -> Bool {
        // `nil` means the recording is over: its capture started on the same queue, earlier.
        guard let captured = await recorder.capturedAudio(from: .max, generation: generation) else { return false }
        guard !isEnded, settings.liveTranscription else { return false }
        guard captured.end >= Self.armingSamples else { return true }
        // Still loading: it may be ready by the next tick.
        guard let loaded = models.loadedEngine else { return true }
        guard let engine = loaded as? any WindowedTranscriptionEngine else { return false }
        transcriber = SegmentedTranscriber(engine: engine, vocabulary: vocabulary())
        let seconds = Double(captured.end) / Self.sampleRate
        Log.timing.info("live armed at \(seconds, format: .fixed(precision: 1))s")
        return true
    }
}
