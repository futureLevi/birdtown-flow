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
    /// Recordings up to this long (30 s) are transcribed whole: one model pass covers them.
    static let segmentedSamples = 480_000
    /// Audio past the last live window beyond this (120 s) is too much to catch up at key-up;
    /// the whole buffer is transcribed instead.
    static let backlogLimit = 1_920_000

    /// Picks segmented (live or offline) or today's whole-buffer path; every fallback inside.
    /// Throws only what today's path throws (CancellationError, ParakeetError, …).
    static func transcript(
        _ samples: [Float], engine: any TranscriptionEngine, vocabulary: [String],
        live: SegmentedTranscriber?, purpose: TranscriptionPurpose, settings: Settings
    ) async throws -> (Transcript, TranscriptionReport) {
        var report = TranscriptionReport()
        let isLong = samples.count > segmentedSamples

        switch purpose {
        case .dictation:
            if let live {
                let reason = await liveRejection(live, samples: samples, engine: engine, vocabulary: vocabulary)
                if let reason {
                    report.fallbackReason = reason
                } else {
                    do {
                        let outcome = try await live.finish(samples)
                        report.path = .segmentedLive
                        report.line = outcome.line
                        return (outcome.transcript, report)
                    } catch let unavailable as SegmentedTranscriber.Unavailable {
                        report.fallbackReason = unavailable.reason
                    }
                }
            } else if isLong, settings.liveTranscription {
                report.fallbackReason = "notArmed"
            }
            if let reason = report.fallbackReason {
                // Frees the engine for the whole-buffer pass. The row and the WAV stay.
                await live?.cancelWork()
                Log.timing.info("live discarded: \(reason, privacy: .public)")
            }

        case .retry:
            if isLong, settings.liveTranscription, let windowed = engine as? any WindowedTranscriptionEngine {
                do {
                    let outcome = try await SegmentedTranscriber.offline(samples, engine: windowed, vocabulary: vocabulary)
                    report.path = .segmentedOffline
                    report.line = outcome.line
                    return (outcome.transcript, report)
                } catch let unavailable as SegmentedTranscriber.Unavailable {
                    report.fallbackReason = unavailable.reason
                    Log.timing.info("retry windows discarded: \(unavailable.reason, privacy: .public)")
                }
            }
        }

        let transcript = try await engine.transcript(samples, vocabulary: vocabulary)
        return (transcript, report)
    }

    /// Why the live windows can't be used for this recording, or `nil` when they can.
    private static func liveRejection(
        _ live: SegmentedTranscriber, samples: [Float], engine: any TranscriptionEngine, vocabulary: [String]
    ) async -> String? {
        if samples.count <= segmentedSamples { return "short" }
        // Windows from the model that was loaded while recording, not the one picked since.
        if (engine as AnyObject) !== (live.engine as AnyObject) { return "engineChanged" }
        if live.vocabulary != vocabulary { return "vocabularyChanged" }
        let lastCut = await live.lastCut
        if samples.count - lastCut > backlogLimit { return "backlog" }
        return nil
    }
}
