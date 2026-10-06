import Foundation

// CONTRACT — owned by the hud agent (feedback design lives with the HUD).

/// Short, quiet interface sounds. Respects `Settings.soundEnabled`.
@MainActor
enum Sounds {
    enum Cue: Sendable {
        /// Microphone opened.
        case start
        /// Hands-free locked on.
        case lock
        /// Recording stopped, processing.
        case stop
        /// Text inserted.
        case done
        /// Cancelled with Esc.
        case cancel
        case error
    }

    static func play(_ cue: Cue) {}
}
