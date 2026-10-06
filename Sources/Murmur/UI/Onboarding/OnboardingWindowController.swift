import AppKit
import SwiftUI

/// Presents first-run onboarding in its own window.
///
/// Closing the window early is always safe: nothing is half-written, permission polling
/// stops, and `hasCompletedOnboarding` stays false so the main window and the menu bar keep
/// offering "Finish setup".
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var model: AppModel?

    var isShowing: Bool { window != nil }

    func show(model: AppModel) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.model = model

        let root = OnboardingView(onFinish: { [weak self] in self?.finish() })
            .environment(model)
        let hosting = NSHostingView(rootView: root)
        // The SwiftUI view has a fixed size; don't let the hosting view resize the window.
        hosting.sizingOptions = []

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.onboardingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Murmur"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = hosting
        window.setContentSize(Layout.onboardingSize)
        window.delegate = self
        window.center()

        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    /// Marks setup complete, closes the window and hands over to the main window.
    private func finish() {
        guard let model else { return }
        model.settings.hasCompletedOnboarding = true
        close()
        model.show(.home)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        model?.permissions.stopPolling()
        window?.delegate = nil
        window = nil
    }
}
