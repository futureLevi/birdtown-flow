import AppKit
import MurmurKit
import SwiftUI

/// The menu bar extra's window: where Murmur stands, one big record button, and the last
/// few dictations a click away.
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
        HStack(spacing: Spacing.m) {
            SetupKit.AppMark(size: Layout.iconLarge, elevated: false)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Murmur")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: Spacing.xs + Spacing.xxs) {
                    SetupKit.StatusDot(color: status.color)
                    Text(status.text)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.top, Spacing.xs)
        .animation(Motion.resolve(Motion.fade, reduceMotion: reduceMotion), value: status.text)
        .accessibilityElement(children: .combine)
    }

    private var status: (text: String, color: Color) {
        if phase.isRecording {
            return (model.controller.isHandsFree ? "Listening · hands-free" : "Listening…", Palette.ember)
        }
        if phase == .transcribing { return ("Transcribing…", Palette.inkTertiary) }
        if phase == .polishing { return ("Polishing…", Palette.inkTertiary) }
        if case .failed(let message) = phase { return (message, Palette.danger) }
        if !micGranted { return ("Microphone access needed", Palette.warning) }
        if !accessibilityGranted { return ("Accessibility access needed", Palette.warning) }
        if !hotkeyActive { return ("Shortcut not active · reopen Murmur", Palette.warning) }
        if let progress = SetupKit.progress(of: modelState) {
            return ("Downloading speech model · \(SetupKit.percent(progress))", Palette.inkTertiary)
        }
        if modelState == .loading || modelState == .downloading(progress: nil) {
            return ("Preparing speech model…", Palette.inkTertiary)
        }
        if SetupKit.isFailed(modelState) { return ("Speech model unavailable", Palette.danger) }
        if modelState == .notDownloaded { return ("Speech model not downloaded", Palette.warning) }
        return ("Ready · Hold \(keyName) to talk", Palette.success)
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
                MenuRow(title: "Finish Setup…", badge: Palette.ember) {
                    guard preview == nil else { return }
                    OnboardingWindowController.shared.show(model: model)
                }
            }
            MenuRow(title: "Paste Last Dictation", shortcut: "⌃⌥V") {
                guard preview == nil else { return }
                model.controller.pasteLast()
            }
            .disabled(model.history.latestWithText == nil)
            MenuRow(title: "Open Murmur") {
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
            MenuRow(title: "Quit Murmur", shortcut: "⌘Q") {
                guard preview == nil else { return }
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
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

/// The menu bar icon: Murmur's five bars, plus an Ember dot while listening or working.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phase = model.controller.phase
        let active = phase.isRecording || phase.isBusy
        Image(nsImage: active ? MenuBarGlyph.active : MenuBarGlyph.idle)
            .accessibilityLabel(active ? "Murmur, listening" : "Murmur")
    }
}

/// Drawn rather than an SF Symbol so it matches the app mark, and so the active variant can
/// carry colour: menu bar extras render SwiftUI images as templates, which drops colour.
@MainActor
enum MenuBarGlyph {
    static let idle = make(active: false)
    static let active = make(active: true)

    /// Icon artwork in points, sized for the menu bar's 22 pt height.
    nonisolated private static func make(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 16), flipped: false) { rect in
            let heights: [CGFloat] = [5, 9, 13, 8, 6]
            let barWidth: CGFloat = 2
            let gap: CGFloat = 1.6
            let dot: CGFloat = 5
            let barsWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            // Leave room on the right for the dot so the bars never shift between states.
            let originX = rect.minX + (rect.width - dot - barsWidth) / 2
            // A template is tinted by the menu bar; the coloured variant must pick the
            // appearance's label colour itself, which resolves at draw time.
            (active ? NSColor.labelColor : NSColor.black).setFill()
            for (index, height) in heights.enumerated() {
                let bar = NSRect(
                    x: originX + CGFloat(index) * (barWidth + gap),
                    y: rect.midY - height / 2,
                    width: barWidth,
                    height: height
                )
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            if active {
                NSColor(Palette.ember).setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - dot, y: rect.maxY - dot - 1, width: dot, height: dot)).fill()
            }
            return true
        }
        image.isTemplate = !active
        image.accessibilityDescription = "Murmur"
        return image
    }
}
