import Foundation
import MurmurDictionary
import MurmurKit

// CONTRACT — owned by the speech agent.

/// Batch speech-to-text: one utterance in, text out.
///
/// Audio is always 16 kHz mono Float32 in [-1, 1] — the recorder converts whatever the
/// microphone produces. Batch rather than streaming on purpose: Parakeet transcribes at
/// ~100× realtime, so a 30-second utterance resolves in a few hundred milliseconds after the
/// key is released, and batch keeps the recording on disk as the single source of truth
/// (which is what makes "retry" in History possible).
protocol TranscriptionEngine: Sendable {
    /// Shown in History, e.g. "Parakeet Ultra".
    var displayName: String { get }

    /// - Parameters:
    ///   - samples: 16 kHz mono Float32.
    ///   - vocabulary: dictionary words to bias toward. May be empty.
    func transcribe(_ samples: [Float], vocabulary: [String]) async throws -> String

    /// `transcribe`, plus the words the engine swapped for dictionary terms on acoustic
    /// evidence, so History can show them next to the dictionary's own corrections.
    func transcript(_ samples: [Float], vocabulary: [String]) async throws -> Transcript
}

extension TranscriptionEngine {
    /// Engines that don't boost have nothing to report.
    func transcript(_ samples: [Float], vocabulary: [String]) async throws -> Transcript {
        Transcript(text: try await transcribe(samples, vocabulary: vocabulary))
    }
}

/// One engine result.
struct Transcript: Sendable {
    var text: String
    /// Words the engine first wrote, rewritten to dictionary terms by vocabulary boosting.
    var boosted: [AppliedCorrection] = []
}

/// An engine that can transcribe a long recording one window at a time
/// (`SegmentedTranscriber`): each window in one model pass, its words timed so the windows
/// can be stitched back together.
protocol WindowedTranscriptionEngine: TranscriptionEngine {
    func transcribeWindow(_ request: WindowRequest) async throws -> WindowTranscript
}

/// One window of a long recording (`SegmentPlanner`).
struct WindowRequest: Sendable {
    /// WAV-equivalent samples (`WAVQuantization`), at most one model pass.
    var audio: [Float]
    /// Where `audio` starts in the recording.
    var startSeconds: Double
    /// The stretch whose words this window keeps, in the recording's seconds.
    var keep: Range<Double>
    /// The last words kept before this window (`SegmentStitcher.Kept.lastWords`), for the
    /// seam check.
    var tail: [SegmentStitcher.TimedWord]
    /// The first word the previous window heard past its cut and left to this one, for the
    /// seam check.
    var following: SegmentStitcher.TimedWord?
    /// Dictionary terms to boost. May be empty.
    var vocabulary: [String]
    /// The window's number, for logs.
    var index: Int
}

/// What one window contributes to the transcript.
struct WindowTranscript: Sendable {
    /// The kept words as decoded, before boosting.
    var kept: SegmentStitcher.Kept
    /// The kept words' text, boosted where the audio supports a dictionary term.
    var text: String
    var boosted: [AppliedCorrection] = []
    var decodeMs: Int
    var boostMs: Int
}

/// A window's tokens don't spell its text, so its words can't be placed. The recording is
/// transcribed whole instead.
struct StitchMismatch: Error {}

enum TranscriptionError: LocalizedError {
    case modelNotReady
    case localeUnsupported(Locale)
    case modelInstallFailed(String)
    case audioUnreadable

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            "The speech model isn't ready yet."
        case .localeUnsupported(let locale):
            "Dictation isn't available for \(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier) on this Mac."
        case .modelInstallFailed:
            // The system's own detail goes to the log where it's thrown; it reads as developer output.
            "Couldn't install the speech model. Try again, or pick another model in Settings."
        case .audioUnreadable:
            "The recording couldn't be read."
        }
    }
}
