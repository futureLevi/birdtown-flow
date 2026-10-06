import AppKit
import Observation
import SwiftUI

/// Owns the floating, non-activating HUD panel and keeps it in sync with the controller.
///
/// The one rule that matters: the panel **never becomes key**. If it did, the user's text
/// field would lose focus and there would be nothing to type into. Buttons still work
/// because the hosting view accepts first mouse and the panel is non-activating.
@MainActor
final class HUDController {
    static let shared = HUDController()

    private var panel: HUDPanel?
    private var model: HUDModel?
    private var lastPhase: DictationController.Phase = .idle
    private var hideTask: Task<Void, Never>?
    private var mouseMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?

    func attach(to app: AppModel) {
        guard panel == nil else { return }
        let model = HUDModel(controller: app.controller, settings: app.settings)
        let panel = HUDPanel(size: Layout.HUD.panelSize)
        let hosting = HUDHostingView(rootView: HUDRootView(model: model))
        // The panel's size is fixed; never let SwiftUI's ideal size resize it.
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Layout.HUD.panelSize)
        panel.contentView = hosting
        self.panel = panel
        self.model = model

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reposition(followMouse: false) }
        }

        Sounds.prepare()
        reposition(followMouse: true)
        observe()
        sync()
    }

    // MARK: - Observation

    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.controller.phase
            _ = model.controller.isHandsFree
            _ = model.settings.showIdlePill
        } onChange: { [weak self] in
            // `onChange` fires before the new value lands; hop to the main actor (which runs
            // after the mutation) to read it, then re-arm.
            Task { @MainActor [weak self] in
                self?.sync()
                self?.observe()
            }
        }
    }

    private func sync() {
        guard let panel, let model else { return }
        let phase = model.controller.phase
        let wantsPanel = phase != .idle || model.settings.showIdlePill

        // A new recording: follow the user to whichever screen the pointer is on.
        if phase == .listening, lastPhase != .listening {
            reposition(followMouse: true)
        }
        lastPhase = phase

        if wantsPanel {
            hideTask?.cancel()
            hideTask = nil
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        } else if panel.isVisible, hideTask == nil {
            // Let the pill finish fading before the window goes away.
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self else { return }
                self.panel?.orderOut(nil)
                self.hideTask = nil
            }
        }
        updateMouseTracking()
    }

    // MARK: - Placement

    /// Bottom-centre of the screen, `Layout.HUD.bottomInset` above the Dock.
    private func reposition(followMouse: Bool) {
        guard let panel else { return }
        let screen = (followMouse ? Self.screenUnderMouse() : panel.screen)
            ?? Self.screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = Layout.HUD.panelSize
        let origin = NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.minY + Layout.HUD.bottomInset - Layout.HUD.shadowMargin).rounded()
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: - Pointer

    /// The panel ignores the mouse except while the pointer is over an interactive pill, so
    /// the transparent area around the pill never swallows a click meant for the app below.
    private func updateMouseTracking() {
        guard let model else { return }
        let interactive = model.state.isInteractive && (panel?.isVisible ?? false)
        if interactive, mouseMonitors.isEmpty {
            // Hop to the main actor rather than asserting we're on it: a wrong assumption
            // there would crash the app, and a hop per mouse move costs nothing.
            let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateHover() }
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                Task { @MainActor [weak self] in self?.updateHover() }
                return event
            }
            mouseMonitors = [global, local].compactMap { $0 }
        } else if !interactive, !mouseMonitors.isEmpty {
            for monitor in mouseMonitors {
                NSEvent.removeMonitor(monitor)
            }
            mouseMonitors.removeAll()
        }
        updateHover()
    }

    private func updateHover() {
        guard let panel, let model else { return }
        var hover: HUDHover?
        if model.state.isInteractive, panel.isVisible {
            let mouse = NSEvent.mouseLocation
            let point = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
            hover = HUDMetrics.hitTest(point, state: model.state)
        }
        if model.hover != hover {
            model.hover = hover
        }
        let ignores = hover == nil
        if panel.ignoresMouseEvents != ignores {
            panel.ignoresMouseEvents = ignores
        }
    }
}

// MARK: - Model

/// Bridges the dictation controller and pointer state into a single `HUDState`.
@MainActor
@Observable
final class HUDModel {
    let controller: DictationController
    let settings: Settings
    var hover: HUDHover?

    init(controller: DictationController, settings: Settings) {
        self.controller = controller
        self.settings = settings
    }

    var state: HUDState {
        HUDState(
            phase: HUDState.Phase(controller.phase),
            showsIdlePill: settings.showIdlePill,
            isHandsFree: controller.isHandsFree,
            level: controller.level,
            levels: controller.levels,
            recordingStartedAt: controller.recordingStartedAt,
            hover: hover,
            keyName: settings.pushToTalkKey.displayName,
            appName: controller.context?.appName,
            notice: controller.notice
        )
    }

    func stop() { controller.stopRecording() }
    func cancel() { controller.cancel() }
    func activate() { controller.toggleRecording() }
}

extension HUDState.Phase {
    init(_ phase: DictationController.Phase) {
        switch phase {
        case .idle: self = .idle
        case .listening: self = .listening
        case .transcribing: self = .transcribing
        case .polishing: self = .polishing
        case .done: self = .done
        case .cancelled: self = .cancelled
        case .failed(let message): self = .failed(message)
        }
    }
}

struct HUDRootView: View {
    let model: HUDModel

    var body: some View {
        HUDView(
            state: model.state,
            actions: HUDActions(
                stop: { model.stop() },
                cancel: { model.cancel() },
                activate: { model.activate() }
            )
        )
    }
}

// MARK: - Window

/// Borderless, transparent, non-activating, and unable to become key or main.
final class HUDPanel: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        // The pill draws its own shadow; AppKit's would outline the whole transparent panel.
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Every click on the HUD is a "first mouse" (the panel is never key), so accept it —
/// otherwise the first click on Stop would be eaten.
final class HUDHostingView: NSHostingView<HUDRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
