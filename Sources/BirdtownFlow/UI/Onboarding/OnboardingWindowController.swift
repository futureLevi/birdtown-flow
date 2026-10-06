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

    func show(model: AppModel) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.model = model

        let root = OnboardingView(initialStep: Self.startStep(for: model), onFinish: { [weak self] in self?.finish() })
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
        window.title = "Welcome to Birdtown Flow"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Paint the canvas colour from the first frame, so nothing flashes before SwiftUI draws.
        window.backgroundColor = NSColor(Palette.canvas)
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

    /// Where setup opens. Unfinished setup with both permissions already granted means a
    /// relaunch after the Accessibility grant (or setup closed part-way), so it resumes at the
    /// speech model instead of making people click through steps that are done. Running
    /// setup again from Settings starts at the beginning.
    private static func startStep(for model: AppModel) -> OnboardingStep {
        model.permissions.refresh()
        let permissionsDone = model.permissions.microphone && model.permissions.accessibility
        return !model.settings.hasCompletedOnboarding && permissionsDone ? .model : .welcome
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
