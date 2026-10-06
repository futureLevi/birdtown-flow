import Foundation

// CONTRACT — owned by the core agent.

/// A microphone the user can pick in Settings.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// Core Audio device UID — stable across reboots and reconnections.
    let uid: String
    let name: String
    let isDefault: Bool

    var id: String { uid }
}

enum AudioDevices {
    /// Every input-capable device, default first.
    static func inputDevices() -> [AudioInputDevice] { [] }
}
