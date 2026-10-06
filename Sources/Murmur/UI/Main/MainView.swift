import AppKit
import Combine
import MurmurKit
import SwiftUI

/// The main window: a sidebar of sections and a quiet detail column.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = preview.status ?? SystemStatus.live(model)
        NavigationSplitView {
            MainSidebar(status: status)
                .navigationSplitViewColumnWidth(Layout.sidebarWidth)
        } detail: {
            ZStack {
                page(status: status)
                    .id(model.section)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
            // Pages cross-fade; the window never slides.
            .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: model.section)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    DictateButton(isRecording: status.isRecording) {
                        model.controller.toggleRecording()
                    }
                }
            }
        }
        // Warm paper shows around the floating sidebar, so the window reads as one surface.
        .background(Palette.canvas)
        .background { SectionShortcuts() }
        .onAppear { model.permissions.refresh() }
        // Accessibility is granted in System Settings; re-check when the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.permissions.refresh()
        }
    }

    @ViewBuilder
    private func page(status: SystemStatus) -> some View {
        switch model.section {
        case .home:
            HomeView(status: status)
        case .history:
            HistoryView(initialQuery: preview.historyQuery, originalRecordID: preview.originalRecordID)
        case .dictionary:
            DictionaryView()
        case .snippets:
            SnippetsView()
        case .style:
            StyleView()
        }
    }
}

/// Start or stop hands-free dictation from the toolbar.
private struct DictateButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isRecording ? "Stop" : "Dictate", systemImage: isRecording ? "stop.fill" : "mic.fill")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.ember)
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .help(isRecording ? "Finish and insert the text (⇧⌘D)"
                          : "Dictate hands-free (⇧⌘D). You can also just hold your shortcut key.")
    }
}

/// ⌘1–⌘5 switch sections, in sidebar order.
private struct SectionShortcuts: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

// MARK: - Sidebar

struct MainSidebar: View {
    let status: SystemStatus
    @Environment(AppModel.self) private var model

    var body: some View {
        let failed = model.history.records.filter { $0.outcome == .failed }.count
        List(selection: selection) {
            ForEach(SidebarSection.allCases) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(section == .history ? failed : 0)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatusView(status: status)
                .padding(Spacing.m)
        }
    }

    private var selection: Binding<SidebarSection?> {
        Binding(
            get: { model.section },
            set: { if let section = $0 { model.section = section } }
        )
    }
}

/// The sidebar footer: is the shortcut armed, is the model ready, are we recording.
struct SidebarStatusView: View {
    let status: SystemStatus
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            shortcutLine
            RowDivider()
            modelLine
        }
        .padding(Spacing.m)
        .cardSurface(radius: Radius.m)
    }

    @ViewBuilder
    private var shortcutLine: some View {
        if status.isRecording {
            HStack(spacing: Spacing.s) {
                StatusDot(color: Palette.ember, isPulsing: true)
                Text("Listening…")
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ember)
                Spacer(minLength: 0)
                Button("Stop") { model.controller.stopRecording() }
                    .buttonStyle(.murmurGhost)
                    .controlSize(.small)
            }
        } else if !status.accessibility {
            Button {
                Permissions.openAccessibilitySettings()
            } label: {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.warning)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Grant Accessibility")
                            .font(Typography.bodyEmphasis)
                            .foregroundStyle(Palette.ink)
                        Text("So \(status.pushToTalkKey) can start dictation")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open System Settings › Privacy & Security › Accessibility")
        } else if !status.hotkeyActive {
            HStack(spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                Text("Shortcut isn't active")
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Button("Retry") { model.controller.activate() }
                    .buttonStyle(.murmurGhost)
                    .controlSize(.small)
            }
        } else {
            HStack(spacing: Spacing.xs + Spacing.xxs) {
                Text("Hold")
                KeyCap(label: status.pushToTalkKey)
                Text("to dictate")
            }
            .font(Typography.callout)
            .foregroundStyle(Palette.inkSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hold \(status.pushToTalkKey) to dictate")
        }
    }

    @ViewBuilder
    private var modelLine: some View {
        switch status.model {
        case .ready:
            HStack(spacing: Spacing.s) {
                StatusDot(color: Palette.success)
                Text("\(status.engineName) ready")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        case .loading:
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.mini)
                Text("Loading \(status.engineName)…")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    Text("Downloading model")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer(minLength: 0)
                    if let progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
                ProgressView(value: progress ?? 0)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(Palette.ink)
            }
        case .notDownloaded:
            HStack(spacing: Spacing.s) {
                StatusDot(color: Palette.inkTertiary)
                Text("Model not downloaded")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 0)
                Button("Get") { Task { await model.models.prepare() } }
                    .buttonStyle(.murmurGhost)
                    .controlSize(.small)
                    .help("Download \(status.engineName) (\(status.engineDownloadSize))")
            }
        case .failed(let message):
            HStack(spacing: Spacing.s) {
                StatusDot(color: Palette.danger)
                Text("Model didn't load")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .help(message)
                Spacer(minLength: 0)
                Button("Retry") { Task { await model.models.prepare() } }
                    .buttonStyle(.murmurGhost)
                    .controlSize(.small)
            }
        }
    }
}
