import Foundation
import MurmurKit

/// Why a recording is being transcribed: a fresh dictation can reuse the windows decoded while
/// it was recorded; a Retry starts from the saved WAV.
enum TranscriptionPurpose: Sendable {
    case dictation
    case retry
}

/// How a recording was transcribed, for the timing summary (`Log.timing`).
struct TranscriptionReport: Sendable {
    enum Path: String, Sendable {
        /// One `TranscriptionEngine.transcript` call on the whole buffer, as for short recordings.
        case whole
        /// Windows decoded while recording, plus the tail at key-up.
        case segmentedLive
        /// A Retry cut into the same windows a live dictation would have used.
        case segmentedOffline
    }

    var path: Path = .whole
    /// Why a segmented path fell back to `.whole`: a fixed token, e.g. "engineChanged".
    var fallbackReason: String?
    /// Sub-timings of the path taken.
    var line = TimingLine("transcribe")
}

/// Transcribes a finished recording: segmented for long ones, whole-buffer otherwise.
@MainActor
enum LongTranscription {
    /// Picks segmented (live or offline) or today's whole-buffer path; every fallback inside.
    /// Throws only what today's path throws (CancellationError, ParakeetError, …).
    static func transcript(
        _ samples: [Float], engine: any TranscriptionEngine, vocabulary: [String],
        live: SegmentedTranscriber?, purpose: TranscriptionPurpose, settings: Settings
    ) async throws -> (Transcript, TranscriptionReport) {
        // Not segmented yet: every recording takes the whole-buffer path.
        let transcript = try await engine.transcript(samples, vocabulary: vocabulary)
        return (transcript, TranscriptionReport())
    }
}
