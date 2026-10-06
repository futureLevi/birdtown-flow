import AppKit
import Foundation
import Observation

/// Live permission state for onboarding and settings. Polls while something is watching,
/// because macOS posts no notification when Accessibility is granted.
@MainActor
@Observable
final class PermissionsMonitor {
    /// Posted on the main thread when Accessibility flips from missing to granted.
    /// `DictationController` listens and re-arms its hotkey, so the two stay decoupled.
    nonisolated static let accessibilityGranted = Notification.Name("com.birdtownlabs.flow.accessibilityGranted")

    private(set) var microphone = false
    private(set) var accessibility = false

    var allGranted: Bool { microphone && accessibility }

    @ObservationIgnored private var timer: Timer?
    /// Lives as long as the monitor, which lives as long as the app; the block holds `self` weakly.
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init() {
        microphone = Permissions.hasMicrophone
        accessibility = Permissions.hasAccessibility
        // Coming back from System Settings is the moment a grant most likely changed.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let microphone = Permissions.hasMicrophone
        let accessibility = Permissions.hasAccessibility
        // Assign only on change, so observers aren't invalidated every poll.
        if microphone != self.microphone { self.microphone = microphone }
        if accessibility != self.accessibility {
            self.accessibility = accessibility
            if accessibility {
                NotificationCenter.default.post(name: Self.accessibilityGranted, object: nil)
            }
        }
    }

    /// Starts polling (≈ every second) until `stopPolling()`.
    func startPolling() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.2
        // `.common` so it keeps ticking while a menu or a drag is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
