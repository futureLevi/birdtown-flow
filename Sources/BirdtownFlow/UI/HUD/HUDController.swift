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
    /// Whether the pointer has moved since the current state appeared. A message only holds
    /// itself open for a pointer that came to it: one that happened to be resting where the
    /// pill appeared (bottom centre, while the user types) must not keep it up forever.
    private var pointerMovedSinceShown = false

    func attach(to app: AppModel) {
        guard panel == nil else { return }
        let model = HUDModel(controller: app.controller, settings: app.settings) { [weak app] followUp in
            guard let app else { return }
            Self.perform(followUp, in: app)
        }
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
            _ = model.controller.notice
            _ = model.controller.followUp
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
        if phase != lastPhase {
            announce(phase, state: model.state)
            pointerMovedSinceShown = false
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
                try? await Task.sleep(for: Motion.pillSettle)
                guard !Task.isCancelled, let self else { return }
                self.panel?.orderOut(nil)
                self.hideTask = nil
            }
        }
        updateMouseTracking()
    }

    // MARK: - VoiceOver

    /// The panel never takes focus, so VoiceOver never lands on it; speak how a dictation
    /// ended instead. Only outcomes are announced: speaking while the mic is open would be
    /// recorded, and the start sound already says listening began.
    private func announce(_ phase: DictationController.Phase, state: HUDState) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let priority: NSAccessibilityPriorityLevel
        switch phase {
        case .failed:
            priority = .high
        case .done:
            // Text that went to the clipboard instead of the field matters more than a plain "Inserted".
            priority = state.notice == nil ? .medium : .high
        case .cancelled:
            priority = .medium
        default:
            return
        }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: state.accessibilityDescription,
                .priority: priority.rawValue,
            ]
        )
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
                Task { @MainActor [weak self] in self?.pointerMoved() }
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                Task { @MainActor [weak self] in self?.pointerMoved() }
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

    private func pointerMoved() {
        pointerMovedSinceShown = true
        updateHover()
    }

    private func updateHover() {
        guard let panel, let model else { return }
        let mouse = NSEvent.mouseLocation
        // Every clickable region lies inside the panel, so a pointer outside it (padded by the
        // hit slop) can only mean "no hover". Most moves happen elsewhere on screen: when
        // nothing is hovered already, there's nothing to update.
        let reach = panel.frame.insetBy(dx: -Layout.HUD.hitSlop, dy: -Layout.HUD.hitSlop)
        if !reach.contains(mouse), model.hover == nil, panel.ignoresMouseEvents { return }

        var hover: HUDHover?
        let state = model.state
        if state.isInteractive, panel.isVisible {
            let point = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
            hover = HUDMetrics.hitTest(point, state: state)
        }
        // A message pill takes the pointer only once the pointer has moved: one that was
        // already resting where the pill appeared (over a chat box near the Dock) must not
        // turn the user's next click into "open History" and pull focus from their app.
        if state.hasAction, !pointerMovedSinceShown {
            hover = nil
        }
        if model.hover != hover {
            model.hover = hover
        }
        // A message with a next step stays while the pointer rests on it, and lingers a
        // moment after it leaves, so it can be read and clicked.
        if state.hasAction {
            model.controller.holdFeedback(hover != nil)
        }
        let ignores = hover == nil
        if panel.ignoresMouseEvents != ignores {
            panel.ignoresMouseEvents = ignores
        }
    }

    // MARK: - Follow-ups

    /// Takes a message's next step. The HUD itself never activates; the window or pane this
    /// opens does, which is the point: the user asked to go there.
    private static func perform(_ followUp: DictationController.FollowUp, in app: AppModel) {
        app.controller.dismissFeedback()
        switch followUp {
        case .record(let id):
            // Reopens the main window if it was closed, then scrolls to and flashes the row.
            app.showHistory(revealing: id)
        case .microphoneAccess:
            Permissions.openMicrophoneSettings()
        case .accessibilityAccess:
            Permissions.openAccessibilitySettings()
        case .inputDevice:
            app.requestSettings(.audio)
            openAppSettings()
        }
    }

    /// The Settings window, through its own ⌘, menu item: SwiftUI opens the Settings scene
    /// only through `openSettings`, which needs a view's environment the HUD doesn't have.
    private static func openAppSettings() {
        NSApp.activate()
        for top in NSApp.mainMenu?.items ?? [] {
            guard let menu = top.submenu,
                  let index = menu.items.firstIndex(where: {
                      $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command && $0.isEnabled
                  })
            else { continue }
            menu.performActionForItem(at: index)
            return
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
    private let onFollowUp: @MainActor (DictationController.FollowUp) -> Void

    init(
        controller: DictationController,
        settings: Settings,
        onFollowUp: @escaping @MainActor (DictationController.FollowUp) -> Void = { _ in }
    ) {
        self.controller = controller
        self.settings = settings
        self.onFollowUp = onFollowUp
    }

    /// Everything but the audio levels. Those change ~30 times a second, so the live content
    /// reads them itself each frame (`liveLevels`) and the rest of the HUD isn't rebuilt per level.
    var state: HUDState {
        HUDState(
            phase: HUDState.Phase(controller.phase),
            showsIdlePill: settings.showIdlePill,
            isHandsFree: controller.isHandsFree,
            recordingStartedAt: controller.recordingStartedAt,
            hover: hover,
            keyName: settings.pushToTalkKey.displayName,
            appName: controller.context?.appName,
            notice: controller.notice,
            actionLabel: controller.followUp.map { Self.label(for: $0) }
        )
    }

    var liveLevels: (level: Float, levels: [Float]) {
        (controller.level, controller.levels)
    }

    func stop() { controller.stopRecording() }
    func cancel() { controller.cancel() }
    func activate() { controller.toggleRecording() }
    func followUp() {
        guard let followUp = controller.followUp else { return }
        onFollowUp(followUp)
    }

    /// What clicking the message does, for VoiceOver and the tooltip.
    static func label(for followUp: DictationController.FollowUp) -> String {
        switch followUp {
        case .record: "Show in History"
        case .microphoneAccess: "Open Microphone settings"
        case .accessibilityAccess: "Open Accessibility settings"
        case .inputDevice: "Choose a microphone"
        }
    }
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
                activate: { model.activate() },
                followUp: { model.followUp() }
            ),
            liveLevels: { model.liveLevels }
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
