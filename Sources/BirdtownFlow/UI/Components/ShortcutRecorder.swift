import AppKit
import MurmurKit
import SwiftUI

/// Records a shortcut: click, press the keys, and the recorder reports what it heard.
///
/// Push-to-talk accepts a modifier pressed and let go on its own (Right ⌥, Left ⌘, fn) or a
/// key with modifiers (⌃⌥D, F5); hands-free and paste-last need a key. Esc, a click anywhere
/// or switching apps cancels. Each recording is checked with `ShortcutRules`; a refused one
/// changes nothing, and `onVerdict` carries the reason for the caller to show beside the row.
///
/// Birdtown Flow's own event tap sees every key before this window does, so pressing the
/// current push-to-talk key here would start a dictation. `onListeningChange` lets the caller
/// pause the shortcuts while listening (`DictationController.deactivate()`) and resume them
/// after (`activate()`), once the new shortcut is saved.
struct ShortcutRecorder: View {
    enum Look {
        /// A secondary pill, e.g. "Record…".
        case button(String)
        /// An inline link inside a sentence.
        case link(String)
        /// The current shortcut as keycaps; click them to record a new one.
        case field
    }

    let role: ShortcutRole
    var look: Look = .field
    /// Drawn by the `.field` look.
    var current: KeyShortcut?
    /// Every action's shortcut now, so a duplicate is refused (`Settings.shortcutsInUse`).
    var inUse: [ShortcutRole: KeyShortcut] = [:]
    /// `true` when listening starts, `false` when it ends (after `onRecord`).
    var onListeningChange: (Bool) -> Void = { _ in }
    /// `nil` when listening starts, so an old message can go; then the verdict on what was
    /// pressed. Not called when the recording is cancelled.
    var onVerdict: (ShortcutVerdict?) -> Void = { _ in }
    /// For snapshots: draw as listening, with these keys held.
    var previewHeld: [String]?
    /// Receives a shortcut `ShortcutRules` accepted.
    let onRecord: (KeyShortcut) -> Void

    @State private var listener: ShortcutListener?
    @State private var held: [String] = []
    @State private var needsKey = false

    private var isListening: Bool { listener != nil || previewHeld != nil }

    var body: some View {
        Group {
            if isListening {
                listening
            } else {
                idle
            }
        }
        .onDisappear { listener?.cancel() }
    }

    @ViewBuilder private var idle: some View {
        switch look {
        case .button(let title):
            // Fixed so a wide control beside it (a picker showing "Double-tap Left Command")
            // squeezes the row's description, never this label down to "…".
            Button(title, action: start)
                .buttonStyle(SetupKit.SecondaryButtonStyle())
                .fixedSize()
                .help(hint)
        case .link(let title):
            Button(title, action: start)
                .buttonStyle(SetupKit.InlineLinkStyle())
                .help(hint)
        case .field:
            Button(action: start) {
                SetupKit.KeyCombo(keys: current?.glyphs ?? [])
            }
            .buttonStyle(KeyFieldButtonStyle())
            .fixedSize()
            // The row's description no longer says to click the keys, so the tooltip does.
            .help("Click to change. \(hint)")
            .accessibilityLabel(current.map { "\($0.spokenName). Record a new shortcut" } ?? "Record a shortcut")
        }
    }

    /// The listening capsule. Not a button: a click anywhere, this included, cancels.
    private var listening: some View {
        let keys = previewHeld ?? held
        let shape = Capsule(style: .continuous)
        return HStack(spacing: Spacing.s) {
            if keys.isEmpty {
                Text(needsKey ? "Add a key…" : "Type shortcut…")
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(Palette.accentInk)
            } else {
                SetupKit.KeyCombo(keys: keys)
            }
            Text("esc")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: Layout.Setup.buttonHeight)
        .background(shape.fill(Palette.accentSoft))
        .overlay(shape.strokeBorder(Palette.accent, lineWidth: Layout.Setup.selectionStroke))
        // Keep the keycaps, the "esc" hint and the whole stroke; the row's description wraps
        // instead.
        .fixedSize()
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording a shortcut. Press the keys, or Escape to cancel.")
        .accessibilityValue(keys.joined(separator: " "))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var hint: String {
        role.allowsLoneModifier
            ? "Press a key you don't type with, like Right ⌥, or a combination like ⌃⌥D."
            : "Press a combination with ⌃, ⌥ or ⌘, like ⌃⌥Space."
    }

    private func start() {
        guard listener == nil, previewHeld == nil else { return }
        held = []
        needsKey = false
        onVerdict(nil)
        let listener = ShortcutListener(
            allowsLoneModifier: role.allowsLoneModifier,
            onUpdate: { keys, needsKey in
                held = keys
                self.needsKey = needsKey
            },
            onFinish: { outcome in finish(outcome) }
        )
        self.listener = listener
        onListeningChange(true)
        listener.start()
    }

    private func finish(_ outcome: ShortcutCapture.Outcome) {
        listener = nil
        held = []
        needsKey = false
        if case .captured(let shortcut) = outcome {
            let verdict = ShortcutRules.check(shortcut, for: role, inUse: inUse)
            if verdict.isAccepted { onRecord(shortcut) }
            onVerdict(verdict)
        }
        onListeningChange(false)
    }
}

/// The `.field` look: the current keycaps in an inset well with a border, so they read as
/// something to click. Hover lifts the border to Signal blue, like the listening capsule the
/// click turns it into.
private struct KeyFieldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyFieldBody(configuration: configuration)
    }
}

private struct KeyFieldBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        let active = hovering && isEnabled
        configuration.label
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: Layout.Setup.buttonHeight)
            .background(shape.fill(active ? Palette.accentSoft : Palette.sunken))
            .overlay(
                shape.strokeBorder(
                    active ? Palette.accent : Palette.hairlineStrong,
                    lineWidth: Layout.Setup.hairline
                )
            )
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? Layout.Setup.pressedOpacity : 1) : Interaction.disabledOpacity)
            .flowFocusRing(shape)
            .onHover { hovering = $0 }
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: hovering)
    }
}

/// A refused or cautioned shortcut, explained under the row that recorded it.
struct ShortcutNotice: View {
    let verdict: ShortcutVerdict

    var body: some View {
        switch verdict {
        case .accepted:
            EmptyView()
        case .caution(let message):
            SetupKit.Callout(
                symbol: "exclamationmark.triangle.fill",
                tint: Palette.warning,
                fill: Palette.warningSoft,
                text: message
            )
        case .rejected(let message):
            SetupKit.Callout(
                symbol: "xmark.octagon.fill",
                tint: Palette.danger,
                fill: Palette.dangerSoft,
                text: "Not changed. \(message)"
            )
        }
    }
}

// MARK: - Listening

/// Feeds key events from this app's windows to a `ShortcutCapture`, swallowing them so a
/// shortcut being recorded never triggers a menu item or types into a field.
@MainActor
final class ShortcutListener {
    private var capture: ShortcutCapture
    private let onUpdate: ([String], Bool) -> Void
    private let onFinish: (ShortcutCapture.Outcome) -> Void
    private var monitor: Any?
    private var resignObserver: (any NSObjectProtocol)?

    init(
        allowsLoneModifier: Bool,
        onUpdate: @escaping ([String], Bool) -> Void,
        onFinish: @escaping (ShortcutCapture.Outcome) -> Void
    ) {
        capture = ShortcutCapture(allowsLoneModifier: allowsLoneModifier)
        self.onUpdate = onUpdate
        self.onFinish = onFinish
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            // Plain values only across the isolation boundary. Local monitors are called from
            // -[NSApplication sendEvent:], on the main thread.
            let type = event.type
            let keyCode = event.keyCode
            let flags = UInt64(event.modifierFlags.rawValue)
            let isKey = type == .keyDown
            let isRepeat = isKey && event.isARepeat
            let typed = isKey ? event.characters(byApplyingModifiers: []) : nil
            let consume = MainActor.assumeIsolated {
                self?.handle(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat, typed: typed) ?? false
            }
            return consume ? nil : event
        }
        // Switching apps means the keys go elsewhere: give up rather than leave the
        // shortcuts paused.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    /// - Returns: whether to swallow the event.
    private func handle(type: NSEvent.EventType, keyCode: UInt16, flags: UInt64, isRepeat: Bool, typed: String?) -> Bool {
        let outcome: ShortcutCapture.Outcome
        switch type {
        case .flagsChanged:
            outcome = capture.modifiersChanged(flags: flags)
        case .keyDown:
            if isRepeat { return true }
            outcome = capture.keyDown(keyCode: keyCode, flags: flags, typed: typed)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // The click still lands where it was aimed.
            finish(.cancelled)
            return false
        default:
            return false
        }

        switch outcome {
        case .listening:
            onUpdate(capture.heldGlyphs, false)
        case .needsKey:
            onUpdate([], true)
        case .captured, .cancelled:
            finish(outcome)
        }
        return true
    }

    private func finish(_ outcome: ShortcutCapture.Outcome) {
        guard monitor != nil else { return }
        stop()
        onFinish(outcome)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
}
