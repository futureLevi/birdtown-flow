import Foundation

/// How long speech to text may take before a dictation or a Retry gives up on it (the
/// transcription watchdog), and the engines' own budgets inside it.
///
/// The watchdog is there for an engine that has stopped answering, not a slow one. A fixed
/// limit that a long recording can't meet on a slow Mac would fail it every time, Retry
/// included, so the limit grows with the audio, well past how fast each engine normally runs.
/// It also stays above the engines' own limits, so their more specific errors are the ones
/// the user sees. Esc stops a dictation whatever the limit.
public enum TranscriptionTimeLimit {
    /// Which kind of engine is transcribing.
    public enum Engine: Sendable, Equatable {
        /// Parakeet on the Neural Engine: 40 to 60 times faster than real time, then
        /// vocabulary boosting (`boost(audioSeconds:)`). A long recording may be decoded
        /// window by window first (`parakeetWindows(audioSeconds:)`).
        case parakeet
        /// Apple's SpeechAnalyzer: far slower, under its own limit (`appleSpeech(audioSeconds:)`).
        case appleSpeech
    }

    /// No recording gets less than this: the fixed limit every recording had before.
    public static let minimum: Double = 60

    /// Parakeet's recognition, per second of audio it decodes: ten times real time, a quarter
    /// of its slowest measured speed.
    static let parakeetRecognition = 0.1
    /// Parakeet, per second of audio, for one pass over the whole recording: recognition
    /// (`parakeetRecognition`) plus boosting's whole budget (0.06 s), rounded up.
    /// FluidAudio's chunks of a long buffer overlap by a few seconds; the margin covers that.
    static let parakeetPerSecond = 0.2
    /// What doesn't grow with the audio: boosting's fixed second, the decoder state, and room
    /// for a Mac busy with something else.
    static let parakeetBase: Double = 10
    /// One window of a long recording is one encoder pass over 15 s, however much of it is
    /// audio (`SegmentPlanner.maximumWindowSamples` fits in one).
    static let parakeetWindowSeconds: Double = 15
    /// Apple Speech resolves its locale and checks its assets before its own limit starts.
    static let appleSpeechMargin: Double = 15

    /// The watchdog's limit, in seconds, for `audioSeconds` of audio: at least `minimum`.
    ///
    /// For Parakeet it covers the most a recording can cost: decoded window by window (a
    /// Retry of a long recording, or what a live one hadn't decoded by key-up), then, when a
    /// window fails late, once more whole.
    public static func seconds(audioSeconds: Double, engine: Engine) -> Double {
        let audio = max(0, audioSeconds)
        let scaled: Double
        switch engine {
        case .parakeet:
            scaled = parakeetBase + parakeetWindows(audioSeconds: audio) + audio * parakeetPerSecond
        case .appleSpeech:
            scaled = appleSpeech(audioSeconds: audio) + appleSpeechMargin
        }
        return max(minimum, scaled)
    }

    /// Parakeet, in seconds, for the windows of `audioSeconds` of audio at their most
    /// (`SegmentPlanner`): a cut every `minSegment` (6 s) and the tail, each window a whole
    /// encoder pass that is boosted on its own budget. Far more work than one pass over the
    /// recording: every window decodes 15 s to keep 6 to 12.
    static func parakeetWindows(audioSeconds: Double) -> Double {
        let config = SegmentPlanner.Config()
        let shortest = Double(config.minSegment) / Double(config.sampleRate)
        let windows = max(0, audioSeconds) / shortest + 1
        let window = parakeetWindowSeconds * parakeetRecognition + boost(audioSeconds: parakeetWindowSeconds)
        return windows * window
    }

    /// Vocabulary boosting's budget, in seconds, for one pass over `audioSeconds` of audio:
    /// a rescoring that overruns it is skipped, never waited for.
    public static func boost(audioSeconds: Double) -> Double {
        1 + max(0, audioSeconds) * 0.06
    }

    /// Apple Speech's own limit, in seconds, for analysing `audioSeconds` of audio. Speech has
    /// a natural ceiling of roughly real time on the slowest Macs; anything well past that is
    /// a stuck analyzer, and the recording is kept for Retry either way.
    public static func appleSpeech(audioSeconds: Double) -> Double {
        15 + max(0, audioSeconds) * 2
    }
}
