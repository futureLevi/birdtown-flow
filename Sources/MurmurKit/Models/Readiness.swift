import Foundation

/// What stands between the user and a working dictation, settled state only, in the order
/// worth fixing. The menu bar names the first one and offers the one action that fixes it.
///
/// The order matters: without Accessibility the shortcut can't exist, so a missing grant
/// outranks an inactive shortcut, and both outrank the speech model, which has a stand-in
/// (Apple Speech) while it isn't ready.
public enum ReadinessIssue: Equatable, Sendable {
    /// Microphone access is off or was never asked for.
    case microphone
    /// Accessibility access is off. TCC keys it to the code signature, so it can lapse by
    /// itself after an update.
    case accessibility
    /// Access is on, but the event tap still can't be created. macOS sometimes wants a fresh
    /// process after the grant.
    case shortcutInactive
    /// The selected speech model failed to download or load.
    case modelFailed
    /// The selected speech model was never downloaded.
    case modelNotDownloaded

    /// The speech model as far as readiness cares.
    public enum Model: Equatable, Sendable {
        case ready
        /// Downloading or loading: it fixes itself, so it's progress, not an issue.
        case preparing
        case notDownloaded
        case failed
    }

    /// The most important thing to fix, or `nil` when everything is in place.
    public static func first(
        microphone: Bool,
        accessibility: Bool,
        hotkeyActive: Bool,
        model: Model
    ) -> ReadinessIssue? {
        if !microphone { return .microphone }
        if !accessibility { return .accessibility }
        if !hotkeyActive { return .shortcutInactive }
        switch model {
        case .failed: return .modelFailed
        case .notDownloaded: return .modelNotDownloaded
        case .ready, .preparing: return nil
        }
    }

    /// The status line beside the dot.
    public var status: String {
        switch self {
        case .microphone: "Microphone access needed"
        case .accessibility: "Accessibility access needed"
        case .shortcutInactive: "Shortcut not active"
        case .modelFailed: "Speech model didn't load"
        case .modelNotDownloaded: "Speech model not downloaded"
        }
    }

    /// Red for something that broke, amber for something waiting on the user.
    public var isFailure: Bool { self == .modelFailed }
}
