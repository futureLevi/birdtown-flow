import Foundation

/// Which engine transcribes while the one selected in Settings isn't ready yet.
///
/// Parakeet is a one-time download of several hundred megabytes, then a first load that can
/// take a while. Dictation shouldn't wait for either: until the selected model is ready, the
/// engine that was loaded before stands in (after switching models), or else Apple Speech,
/// which macOS provides. Once the selected model is ready it takes over by itself. History
/// records which engine actually ran, so a stand-in is never hidden.
public enum EngineFallback {
    /// The name History and the UI use for macOS's built-in engine.
    public static let appleSpeech = "Apple Speech"

    /// The engine that transcribes in place of `selected`, or `nil` when `selected` is ready
    /// or nothing can stand in for it.
    ///
    /// - Parameters:
    ///   - selected: the engine chosen in Settings.
    ///   - selectedIsDownloadable: whether `selected` is a downloadable model (Parakeet). Apple
    ///     Speech can't stand in for itself.
    ///   - selectedReady: whether `selected` is loaded and serving dictations.
    ///   - loaded: the engine still loaded from before a switch, if any.
    public static func standIn(
        selected: String,
        selectedIsDownloadable: Bool,
        selectedReady: Bool,
        loaded: String?
    ) -> String? {
        guard !selectedReady else { return nil }
        if let loaded, !loaded.isEmpty, loaded != selected { return loaded }
        return selectedIsDownloadable ? appleSpeech : nil
    }

    /// "Using Apple Speech until Parakeet Ultra is ready", with " · 42%" when the download's
    /// progress is known.
    public static func note(standIn: String, selected: String, progress: String? = nil) -> String {
        let note = "Using \(standIn) until \(selected) is ready"
        guard let progress, !progress.isEmpty else { return note }
        return "\(note) · \(progress)"
    }

    /// Whether a dictation was transcribed by a stand-in rather than the selected engine,
    /// judged from the engine name its History record carries. Names are compared loosely
    /// ("Parakeet v2" is "Parakeet v2 (English)") so a display suffix can't fake a stand-in.
    public static func ranOnStandIn(recordEngine: String, selected: String) -> Bool {
        let ran = recordEngine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ran.isEmpty else { return false }
        return !(selected.hasPrefix(ran) || ran.hasPrefix(selected))
    }
}
