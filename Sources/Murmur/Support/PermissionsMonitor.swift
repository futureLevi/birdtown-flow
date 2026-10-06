import Foundation
import Observation

// CONTRACT — owned by the core agent.

/// Live permission state for onboarding and settings. Polls while something is watching,
/// because macOS posts no notification when Accessibility is granted.
@MainActor
@Observable
final class PermissionsMonitor {
    private(set) var microphone = false
    private(set) var accessibility = false

    var allGranted: Bool { microphone && accessibility }

    init() {
        refresh()
    }

    func refresh() {
        microphone = Permissions.hasMicrophone
        accessibility = Permissions.hasAccessibility
    }

    /// Starts polling (≈ every second) until `stopPolling()`.
    func startPolling() {}

    func stopPolling() {}
}
