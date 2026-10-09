import AppKit
import MurmurKit
import SwiftUI

/// The menu bar extra's window: where Birdtown Flow stands, one big record button, and the
/// last few dictations a click away.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.setupPreview) private var preview
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedID: UUID?

    private var phase: DictationController.Phase { preview?.phase ?? model.controller.phase }
    private var modelState: ModelManager.State { preview?.modelState ?? model.models.state }
    private var micGranted: Bool { preview.map { $0.microphone == .granted } ?? model.permissions.microphone }
    private var accessibilityGranted: Bool { preview?.accessibility ?? model.permissions.accessibility }
    private var hotkeyActive: Bool { preview?.hotkeyActive ?? model.controller.isHotkeyActive }
    private var keyName: String { SetupKit.name(for: model.settings.pushToTalkKey) }
    private var canRelaunch: Bool { preview?.canRelaunch ?? SetupKit.canRelaunch }
    /// What transcribes while the selected model downloads or loads (usually Apple Speech).
    private var standIn: String? {
        if let preview { return SetupKit.standIn(for: model.settings.engine, state: preview.modelState) }
        return model.models.standInName
    }

    /// The first thing keeping dictation from working, if any. The status line names it and
    /// the row under it fixes it.
    private var issue: ReadinessIssue? {
        ReadinessIssue.first(
            microphone: micGranted,
            accessibility: accessibilityGranted,
            hotkeyActive: hotkeyActive,
            model: Self.readiness(of: modelState)
        )
    }

    private static func readiness(of state: ModelManager.State) -> ReadinessIssue.Model {
        switch state {
        case .ready: .ready
        case .downloading, .loading: .preparing
        case .notDownloaded: .notDownloaded
        case .failed: .failed
        }
    }
    /// Lazily, so a long history isn't scanned in full every time the menu draws.
    private var recent: [HistoryRecord] {
        Array(model.history.records.lazy.filter { $0.hasText && !model.historyDeletion.isHidden($0.id) }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header
            // Until setup is finished, "Finish Setup…" is the fix: onboarding asks for each
            // grant and lets the user choose a model before anything downloads.
            if let issue, model.settings.hasCompletedOnboarding {
                fixRows(for: issue)
                    .transition(.opacity)
            }
            recordButton
            if !recent.isEmpty {
                recentSection
            }
            Rectangle().fill(Palette.hairline).frame(height: Layout.Setup.hairline)
            actions
        }
        .padding(Spacing.m)
        .frame(width: Layout.Setup.menuBarWidth)
        .background(Palette.canvas)
        .animation(Motion.resolve(Motion.fade, reduceMotion: reduceMotion), value: issue)
        // macOS posts nothing when a grant changes, and a menu bar app is rarely the active
        // app, so check while the menu is open: a lapsed grant shows up the moment the user
        // looks, and a fixed one clears while they watch.
        .onAppear {
            guard preview == nil else { return }
            model.permissions.startPolling(.menuBar)
        }
        .onDisappear {
            guard preview == nil else { return }
            model.permissions.stopPolling(.menuBar)
        }
    }

    // MARK: Header

    private var header: some View {
        // The icon's frame includes the artwork's transparent margin, so a tighter gap here
        // reads as the same rhythm as the rows below.
        HStack(spacing: Spacing.s) {
            SetupKit.AppMark(size: Layout.Setup.menuIcon, elevated: false)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Birdtown Flow")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: Spacing.xs + Spacing.xxs) {
                    indicator(status.indicator)
                        .frame(width: Layout.Orb.small, height: Layout.Orb.small)
                    Text(status.text)
                        .font(Typography.callout)
                        .foregroundStyle(status.indicator == .live ? Palette.ink : Palette.inkSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                if let standInDetail {
                    // The percentage sits apart from the note so it stays at the end of the
                    // first line however the note wraps, instead of orphaning on the second.
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(standInDetail)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let progress = SetupKit.progress(of: modelState) {
                            Text(SetupKit.percent(progress))
                                .font(Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(Palette.inkSecondary)
                                .contentTransition(.numericText())
                                .layoutPriority(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xxs)
        .animation(Motion.resolve(Motion.fade, reduceMotion: reduceMotion), value: status.text)
        .accessibilityElement(children: .combine)
    }

    /// What sits beside the status text: the spectrum while your voice is live or being worked
    /// on, a plain dot for every settled state.
    private enum Indicator: Equatable {
        case dot(Color)
        case live
        case thinking
    }

    @ViewBuilder
    private func indicator(_ indicator: Indicator) -> some View {
        switch indicator {
        case .dot(let color):
            SetupKit.StatusDot(color: color)
        case .live:
            LiveOrb(phase: orbPhase)
        case .thinking:
            SpectrumOrb(mode: .thinking, diameter: Layout.Orb.small, phase: orbPhase)
        }
    }

    /// Snapshots draw orbs at a fixed moment; live, they animate.
    private var orbPhase: Double? { preview == nil ? nil : Motion.snapshotOrbPhase }

    private var status: (text: String, indicator: Indicator) {
        if phase.isRecording {
            return (model.controller.isHandsFree ? "Listening · hands-free" : "Listening…", .live)
        }
        if phase == .transcribing { return ("Transcribing…", .thinking) }
        if phase == .polishing { return ("Polishing…", .thinking) }
        if phase == .done {
            // The controller's notice when it couldn't be typed, e.g. it was copied instead.
            return (model.controller.notice ?? "Done", .dot(Palette.success))
        }
        if phase == .cancelled { return ("Cancelled", .dot(Palette.inkTertiary)) }
        if case .failed(let message) = phase { return (message, .dot(Palette.danger)) }
        if let issue { return (issue.status, .dot(Self.badge(for: issue))) }
        // Downloading doesn't stop dictation: a stand-in transcribes meanwhile, and the line
        // under the status says which (`standInDetail`).
        if standIn != nil, SetupKit.progress(of: modelState) != nil || modelState == .downloading(progress: nil) {
            return ("Ready · Hold \(keyName) to dictate", .dot(Palette.success))
        }
        if let progress = SetupKit.progress(of: modelState) {
            return ("Downloading speech model · \(SetupKit.percent(progress))", .dot(Palette.inkTertiary))
        }
        if modelState == .loading || modelState == .downloading(progress: nil) {
            return ("Preparing speech model…", .dot(Palette.inkTertiary))
        }
        return ("Ready · Hold \(keyName) to dictate", .dot(Palette.success))
    }

    /// "Using Apple Speech until Parakeet Ultra is ready", under the status while the selected
    /// model downloads or loads, so it's clear what's transcribing; the header adds the
    /// download's percentage beside it. Hidden while a dictation is on screen, and when the
    /// status already names a problem.
    private var standInDetail: String? {
        guard phase == .idle, issue == nil else { return nil }
        guard modelState == .loading || modelState == .downloading(progress: nil)
                || SetupKit.progress(of: modelState) != nil
        else { return nil }
        guard let standIn else { return nil }
        return EngineFallback.note(standIn: standIn, selected: model.settings.engine.displayName)
    }

    // MARK: Fix

    /// Red for something that broke, amber for something waiting on the user.
    private static func badge(for issue: ReadinessIssue) -> Color {
        issue.isFailure ? Palette.danger : Palette.warning
    }

    /// The one action that fixes `issue`, right under the status that names it.
    @ViewBuilder
    private func fixRows(for issue: ReadinessIssue) -> some View {
        let badge = Self.badge(for: issue)
        // A little air between rows, so a second action doesn't read as the first one's caption.
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            switch issue {
            case .microphone:
                MenuRow(title: "Allow Microphone Access…", badge: badge) {
                    guard preview == nil else { return }
                    allowMicrophone()
                }
                .help("Ask for the microphone, or open System Settings › Privacy & Security › Microphone")
            case .accessibility:
                // TCC keys the grant to the code signature, so after an update the switch
                // can still show on while macOS ignores it.
                MenuRow(
                    title: "Open Accessibility Settings…",
                    detail: "Already on? Turn Birdtown Flow off and on again.",
                    badge: badge
                ) {
                    guard preview == nil else { return }
                    // The prompt adds Birdtown Flow to the list if it's missing from it.
                    Permissions.promptForAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                .help("Open System Settings › Privacy & Security › Accessibility")
            case .shortcutInactive:
                MenuRow(
                    title: canRelaunch ? "Restart Birdtown Flow" : "Try Again",
                    detail: "macOS sometimes needs a fresh start to hear your shortcut.",
                    badge: badge
                ) {
                    guard preview == nil else { return }
                    restoreShortcut()
                }
                // Restarting mid-dictation would lose what's being said.
                .disabled(phase.isRecording || phase.isBusy)
            case .modelNotDownloaded:
                MenuRow(
                    title: "Download Speech Model",
                    detail: "\(model.settings.engine.displayName) · \(model.settings.engine.downloadSize)",
                    badge: badge
                ) {
                    guard preview == nil else { return }
                    // Unstructured on purpose: closing the menu must not cancel the download.
                    Task { await model.models.prepare() }
                }
            case .modelFailed:
                MenuRow(title: "Try Again", detail: failureReason, badge: badge) {
                    guard preview == nil else { return }
                    Task { await model.models.prepare() }
                }
                // When trying again can't help (no space, an unsupported Mac), another
                // model can.
                MenuRow(title: "Speech Settings…", alignsWithBadge: true) {
                    guard preview == nil else { return }
                    model.showSettings(.audio)
                }
            }
        }
    }

    /// Why the model failed, in the words ModelManager chose for it.
    private var failureReason: String? {
        guard case .failed(let message) = modelState, !message.isEmpty else { return nil }
        return message
    }

    /// Asks the first time; after a "Don't Allow", macOS won't ask again, so open the
    /// setting instead.
    private func allowMicrophone() {
        Task {
            let granted = await Permissions.requestMicrophone()
            model.permissions.refresh()
            if !granted { Permissions.openMicrophoneSettings() }
        }
    }

    /// Re-arms the shortcut; if macOS still refuses the event tap, restarts the app, which
    /// is what it usually wants after a grant. Pending deletes are committed on the way out.
    private func restoreShortcut() {
        if model.controller.activate() { return }
        guard canRelaunch else { return }
        SetupKit.relaunch()
    }

    // MARK: Record

    private var recordButton: some View {
        Button {
            guard preview == nil else { return }
            model.controller.toggleRecording()
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: phase.isRecording ? "stop.fill" : "mic.fill")
                    .contentTransition(.symbolEffect(.replace))
                Text(phase.isRecording ? "Stop Dictating" : "Start Dictating")
            }
            .frame(minHeight: Layout.Setup.menuButtonHeight)
        }
        .buttonStyle(SetupKit.PrimaryButtonStyle(fullWidth: true))
        .disabled(phase.isBusy)
        .help(phase.isRecording ? "Finish and type what you said" : "Start listening hands-free")
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Recent")
                .eyebrowStyle()
                .padding(.horizontal, Spacing.s)
                .padding(.bottom, Spacing.xxs)
            ForEach(recent) { record in
                RecentRow(record: record, copied: copiedID == record.id) { copy(record) }
            }
        }
    }

    private func copy(_ record: HistoryRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.finalText, forType: .string)
        withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) { copiedID = record.id }
        Task {
            try? await Task.sleep(for: Motion.confirmationHold)
            guard copiedID == record.id else { return }
            withAnimation(Motion.resolve(Motion.fade, reduceMotion: reduceMotion)) { copiedID = nil }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 0) {
            if !model.settings.hasCompletedOnboarding {
                // A call to action, not a live state: Signal blue.
                MenuRow(title: "Finish Setup…", badge: Palette.accent) {
                    guard preview == nil else { return }
                    OnboardingWindowController.shared.show(model: model)
                }
            }
            // Only advertise the shortcut while it's switched on in Settings.
            MenuRow(
                title: "Paste Last Dictation",
                shortcut: model.settings.pasteLastShortcutEnabled ? model.settings.pasteLastShortcut.displayName : nil
            ) {
                guard preview == nil else { return }
                model.controller.pasteLast()
            }
            .disabled(model.history.latestWithText == nil)
            MenuRow(title: "Open Birdtown Flow", shortcut: "⌘O") {
                guard preview == nil else { return }
                openWindow(id: "main")
                model.show(.home)
            }
            .keyboardShortcut("o", modifiers: .command)
            MenuRow(title: "Settings…", shortcut: "⌘,") {
                guard preview == nil else { return }
                model.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "Quit Birdtown Flow", shortcut: "⌘Q") {
                guard preview == nil else { return }
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// The listening orb, swelling with the voice. Its own view so the level, which changes
/// about 30 times a second, redraws only the orb and not the whole menu.
private struct LiveOrb: View {
    let phase: Double?
    @Environment(AppModel.self) private var model

    var body: some View {
        SpectrumOrb(
            mode: .live,
            diameter: Layout.Orb.small,
            level: phase == nil ? model.controller.level : 0,
            phase: phase
        )
    }
}

// MARK: - Rows

private struct RecentRow: View {
    let record: HistoryRecord
    let copied: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(record.finalText)
                    .font(Typography.transcriptSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: .leading) {
                    Label("Copied", systemImage: "checkmark")
                        .foregroundStyle(Palette.success)
                        .opacity(copied ? 1 : 0)
                    Text(meta)
                        .foregroundStyle(Palette.inkTertiary)
                        .opacity(copied ? 0 : 1)
                }
                .font(Typography.caption)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.s)
        }
        .buttonStyle(MenuRowButtonStyle(drawsFocusRing: isFocused))
        // The style draws a Signal blue focus ring in the row's own shape.
        .focusEffectDisabled()
        .focused($isFocused)
        .help("Copy to the clipboard")
        .accessibilityLabel(record.finalText)
        .accessibilityHint(copied ? "Copied" : "Copies to the clipboard")
    }

    private var meta: String {
        let time = record.createdAt.formatted(.relative(presentation: .named))
        guard let app = record.context?.appName else { return time }
        return "\(app) · \(time)"
    }
}

private struct MenuRow: View {
    let title: String
    /// A second, smaller line: what the action will do or why it's offered.
    var detail: String?
    var shortcut: String?
    var badge: Color?
    /// Leaves the badge's space empty, so a secondary row lines up with a badged one above it.
    var alignsWithBadge = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            // Baseline-aligned, so the dot and the shortcut sit on the title's line rather than
            // centring on a title-and-detail block.
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                if badge != nil || alignsWithBadge {
                    // A hidden line of title text carries the baseline; the dot centres on it.
                    Text(verbatim: " ")
                        .font(Typography.body)
                        .frame(width: Layout.Main.statusDot)
                        .hidden()
                        .overlay {
                            if let badge { SetupKit.StatusDot(color: badge) }
                        }
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(isEnabled ? Palette.ink : Palette.inkTertiary)
                    if let detail {
                        Text(detail)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Spacing.s)
                if let shortcut {
                    Text(shortcut)
                        .font(Typography.keycap)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, detail == nil ? 0 : Spacing.xs)
            .frame(minHeight: Layout.rowMinHeight - Spacing.l)
        }
        .buttonStyle(MenuRowButtonStyle(drawsFocusRing: isFocused))
        // The style draws a Signal blue focus ring in the row's own shape.
        .focusEffectDisabled()
        .focused($isFocused)
    }
}

/// A menu window row: a well on hover that deepens while pressed, like a native menu item,
/// and a Signal blue ring in the row's shape under keyboard focus. Pass the button's own
/// focus as `drawsFocusRing` and put `.focusEffectDisabled()` on the button.
private struct MenuRowButtonStyle: ButtonStyle {
    var drawsFocusRing = false

    func makeBody(configuration: Configuration) -> some View {
        MenuRowButtonBody(configuration: configuration, drawsFocusRing: drawsFocusRing)
    }
}

private struct MenuRowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let drawsFocusRing: Bool

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        configuration.label
            .background(shape.fill(fill))
            .contentShape(shape)
            .flowFocusRing(shape, drawn: drawsFocusRing)
            .onHover { hovering = $0 }
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: hovering)
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var fill: Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed { return Palette.surfacePressed }
        return hovering ? Palette.surfaceHover : .clear
    }
}

// MARK: - Menu bar icon

/// The menu bar icon: the logo's five bars, plus a tiny spectrum disc while listening or working.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phase = model.controller.phase
        let active = phase.isRecording || phase.isBusy
        Image(nsImage: active ? MenuBarGlyph.active : MenuBarGlyph.idle)
            .accessibilityLabel(active ? "Birdtown Flow, listening" : "Birdtown Flow")
    }
}

/// Drawn rather than an SF Symbol so it matches the app mark, and so the active variant can
/// carry colour: menu bar extras render SwiftUI images as templates, which drops colour.
@MainActor
enum MenuBarGlyph {
    static let idle = make(active: false)
    static let active = make(active: true)

    /// Icon artwork in points, sized for the menu bar's 22 pt height: the logo's five
    /// mirrored bars, in its exact proportions (`LogoBars`). While listening, a tiny spectrum
    /// disc (the logo's own, from `LogoPainter`) sits top right with a point of clear space,
    /// so it reads as the live light rather than part of the mark. Both states share one
    /// canvas so the status item never changes width.
    nonisolated private static func make(active: Bool) -> NSImage {
        // y-down, which is what `LogoPainter` expects.
        let image = NSImage(size: NSSize(width: 21, height: 19), flipped: true) { rect in
            let tallest: CGFloat = 14
            let heights: [CGFloat] = [0.345, 0.658, 1, 0.658, 0.345].map { $0 * tallest }
            let barWidth: CGFloat = 0.164 * tallest
            let pitch: CGFloat = 0.278 * tallest
            let originX = rect.minX + 0.5
            // A template is tinted by the menu bar; the coloured variant must pick the
            // appearance's label colour itself, which resolves at draw time.
            (active ? NSColor.labelColor : NSColor.black).setFill()
            for (index, height) in heights.enumerated() {
                let bar = NSRect(
                    x: originX + CGFloat(index) * pitch,
                    y: rect.midY - height / 2,
                    width: barWidth,
                    height: height
                )
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            if active, let cg = NSGraphicsContext.current?.cgContext {
                // Top right, above the short outer bar: 6 pt still reads as the spectrum at
                // 16 px, and this corner leaves a point clear of both neighbouring bars.
                let radius: CGFloat = 3
                LogoPainter.drawDisc(
                    in: cg,
                    centre: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius
                )
            }
            return true
        }
        image.isTemplate = !active
        image.accessibilityDescription = "Birdtown Flow"
        return image
    }
}
