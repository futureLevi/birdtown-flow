import Foundation

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
}

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
            "Dictation isn't available for \(locale.identifier) on this Mac."
        case .modelInstallFailed(let detail):
            "Couldn't install the speech model: \(detail)"
        case .audioUnreadable:
            "The recording couldn't be read."
        }
    }
}
