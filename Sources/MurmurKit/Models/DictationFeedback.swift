import Foundation

/// What the HUD tells the user when a dictation ends without the usual check: a recording
/// that heard nothing, or text that went in without its AI polish. Pure decisions and copy,
/// so they're tested here and the app only shows them.
public enum DictationFeedback {
    /// What a finished recording turned out to be, before it reaches the speech engine.
    public enum Recording: Equatable, Sendable {
        /// A slip or a short tap: dropped without a trace (no sound, no message, no History row).
        case drop
        /// Long enough to be deliberate, but the microphone stayed silent the whole time:
        /// usually a muted or wrong input device. Worth telling the user.
        case noSpeech
        /// Something was heard; transcribe it.
        case speech
    }

    /// Classifies a recording.
    ///
    /// - Parameters:
    ///   - duration: seconds of audio captured.
    ///   - peakLevel: the loudest meter level seen, 0…1.
    ///   - minimumAudio: shorter than this is never a dictation.
    ///   - silenceLevel: a peak below this means the microphone heard nothing.
    ///   - noSpeechNotice: a silent recording at least this long gets a "didn't hear anything"
    ///     message; a shorter one (a hesitant press) is dropped quietly.
    public static func classify(
        duration: Double,
        peakLevel: Float,
        minimumAudio: Double,
        silenceLevel: Float,
        noSpeechNotice: Double
    ) -> Recording {
        guard duration >= minimumAudio else { return .drop }
        guard peakLevel < silenceLevel else { return .speech }
        return duration >= noSpeechNotice ? .noSpeech : .drop
    }

    /// The longest microphone name the no-speech message spells out before it truncates.
    public static let deviceNameLimit = 32

    /// "Didn't hear anything · check MacBook Pro Microphone". Names the input device when it's
    /// known, since the usual cause is the wrong one (AirPods that just connected).
    public static func noSpeechMessage(deviceName: String?) -> String {
        let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "Didn't hear anything · check your microphone" }
        let shown = name.count > deviceNameLimit
            ? String(name.prefix(deviceNameLimit - 1)).trimmingCharacters(in: .whitespaces) + "…"
            : name
        return "Didn't hear anything · check \(shown)"
    }

    /// The engine heard sound but recognised no words. Points at History only while the
    /// recording is still there to play or retry ("Keep no audio" drops it at once).
    public static func noWordsMessage(audioSaved: Bool) -> String {
        audioSaved ? "Didn't catch any words · it's saved in History" : "Didn't catch any words"
    }

    /// The HUD notice for text inserted without its AI polish, from the fallback note
    /// `PolishService` writes to History ("timed out", "No API key").
    ///
    /// `nil` when there's nothing to say: no note (polished, or polish is off), or the guard
    /// rejected a rewrite that changed what was said. That's polish doing its job, not a
    /// fault, and it would otherwise nag on every borderline sentence.
    public static func polishNotice(for note: String?) -> String? {
        guard var note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        if note.lowercased().hasPrefix(guardRejectionPrefix) { return nil }
        while note.hasSuffix(".") { note.removeLast() }
        guard let first = note.first else { return nil }
        return "Inserted without polish · " + first.uppercased() + String(note.dropFirst())
    }

    /// How `PolishService` begins the note for a rewrite `PolishGuard` turned down.
    static let guardRejectionPrefix = "rewrite rejected"
}
