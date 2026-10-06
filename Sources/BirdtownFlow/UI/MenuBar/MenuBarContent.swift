import AppKit
import MurmurKit
import SwiftUI

/// The menu bar extra's window: where Birdtown Flow stands, one big record button, and the
/// last few dictations a click away.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.setupPreview) private var preview
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedID: UUID?

    private var phase: DictationController.Phase { preview?.phase ?? model.controller.phase }
    private var modelState: ModelManager.State { preview?.modelState ?? model.models.state }
    private var micGranted: Bool { preview.map { $0.microphone == .granted } ?? model.permissions.microphone }
    private var accessibilityGranted: Bool { preview?.accessibility ?? model.permissions.accessibility }
    private var hotkeyActive: Bool { preview?.hotkeyActive ?? model.controller.isHotkeyActive }
    private var keyName: String { SetupKit.name(for: model.settings.pushToTalkKey) }
    /// Lazily, so a long history isn't scanned in full every time the menu draws.
    private var recent: [HistoryRecord] { Array(model.history.records.lazy.filter(\.hasText).prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header
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
        if !micGranted { return ("Microphone access needed", .dot(Palette.warning)) }
        if !accessibilityGranted { return ("Accessibility access needed", .dot(Palette.warning)) }
        if !hotkeyActive { return ("Shortcut not active · reopen Birdtown Flow", .dot(Palette.warning)) }
        if let progress = SetupKit.progress(of: modelState) {
            return ("Downloading speech model · \(SetupKit.percent(progress))", .dot(Palette.inkTertiary))
        }
        if modelState == .loading || modelState == .downloading(progress: nil) {
            return ("Preparing speech model…", .dot(Palette.inkTertiary))
        }
        if SetupKit.isFailed(modelState) { return ("Speech model unavailable", .dot(Palette.danger)) }
        if modelState == .notDownloaded { return ("Speech model not downloaded", .dot(Palette.warning)) }
        return ("Ready · Hold \(keyName) to talk", .dot(Palette.success))
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
                Text(phase.isRecording ? "Stop Dictation" : "Start Dictation")
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
            MenuRow(title: "Paste Last Dictation", shortcut: "⌃⌥V") {
                guard preview == nil else { return }
                model.controller.pasteLast()
            }
            .disabled(model.history.latestWithText == nil)
            MenuRow(title: "Open Birdtown Flow") {
                guard preview == nil else { return }
                openWindow(id: "main")
                model.show(.home)
            }
            MenuRow(title: "Settings…", shortcut: "⌘,") {
                guard preview == nil else { return }
                NSApp.activate()
                openSettings()
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
    @State private var hovering = false

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
            .background(
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(hovering ? Palette.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
    var shortcut: String?
    var badge: Color?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if let badge {
                    SetupKit.StatusDot(color: badge)
                }
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(isEnabled ? Palette.ink : Palette.inkTertiary)
                Spacer(minLength: Spacing.s)
                if let shortcut {
                    Text(shortcut)
                        .font(Typography.keycap)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: Layout.rowMinHeight - Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(hovering && isEnabled ? Palette.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
