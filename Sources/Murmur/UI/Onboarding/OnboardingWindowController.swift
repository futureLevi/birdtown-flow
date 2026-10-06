import AppKit
import SwiftUI

// PLACEHOLDER — owned by the ui-setup agent.

/// Presents first-run onboarding in its own window.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {}

    func close() {
        window?.close()
        window = nil
    }
}
