import Foundation
import Observation

// CONTRACT — owned by the speech agent. Placeholder bodies until the real one lands.

/// Owns the speech model: download, load, warm-up, and vending the engine.
@MainActor
@Observable
final class ModelManager {
    enum State: Equatable {
        case notDownloaded
        /// `progress` is 0…1 when known.
        case downloading(progress: Double?)
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded

    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    /// Whether the model files for `choice` are already on disk.
    func isDownloaded(_ choice: SpeechEngineChoice) -> Bool {
        choice == .apple
    }

    /// Downloads (if needed), loads and warms up the selected engine. Safe to call repeatedly;
    /// concurrent callers share one load.
    func prepare() async {}

    /// The ready engine for the current setting. Waits for `prepare()` if a load is running.
    func engine() async throws -> any TranscriptionEngine {
        throw TranscriptionError.modelNotReady
    }

    /// Removes downloaded files for `choice` to reclaim disk space.
    func deleteModel(_ choice: SpeechEngineChoice) {}
}
