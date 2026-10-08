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
                // Settings one click away from anywhere in the window, at the leading edge.
                ToolbarItem(placement: .navigation) {
                    SettingsToolbarButton()
                }
                // The name, centred, where a document window would show its title.
                ToolbarItem(placement: .principal) {
                    ToolbarWordmark()
                }
                // A wordmark, not a control: no glass capsule behind it.
                .sharedBackgroundVisibility(.hidden)
            }
        }
        // Signal blue for every system control: sidebar selection, toggles, focus rings.
        .tint(Palette.accent)
        // Porcelain (midnight in dark mode) shows around the floating sidebar, so the window
        // reads as one surface.
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
        case .lab:
            LabView()
        }
    }
}

/// Opens Settings from the main window's toolbar, so it's never a trip through the menu bar.
struct SettingsToolbarButton: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.mainPreview) private var preview

    var body: some View {
        Button {
            guard preview.status == nil else { return }
            openSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .help("Settings (⌘,)")
    }
}

/// The app icon and name, centred in the toolbar.
struct ToolbarWordmark: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            AppIconArtwork(size: Layout.Main.toolbarIcon, showsShadow: false)
            Text("Birdtown Flow")
                .font(Typography.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Birdtown Flow")
        .accessibilityAddTraits(.isHeader)
    }
}

/// ⌘1–⌘6 switch sections, in sidebar order.
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
            ForEach(SidebarSection.everyday) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(section == .history ? failed : 0)
                    .tag(section)
            }
            Section("Admin") {
                ForEach(SidebarSection.admin) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
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
    @Environment(\.mainPreview) private var preview

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
                SpectrumOrb(mode: .live, diameter: Layout.Orb.small, phase: preview.orbPhase)
                Text("Listening…")
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Button("Stop") { model.controller.stopRecording() }
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
            }
        } else if !status.accessibility {
            Button {
                Permissions.openAccessibilitySettings()
            } label: {
                statusLines(
                    title: "Allow Accessibility",
                    detail: "Needed for your shortcut",
                    symbol: "exclamationmark.triangle.fill"
                ) {
                    Image(systemName: "arrow.up.forward")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open System Settings › Privacy & Security › Accessibility")
        } else if !status.hotkeyActive {
            statusLines(
                title: "Shortcut paused",
                detail: "Reconnecting automatically…",
                symbol: "exclamationmark.triangle.fill"
            ) {
                Button("Retry") { model.controller.activate() }
                    .buttonStyle(.flowGhost)
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

    /// One title line (with a warning glyph and a trailing accessory) over one detail line.
    /// Both stay on a single line at sidebar width.
    private func statusLines<Accessory: View>(
        title: String,
        detail: String,
        symbol: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.warning)
                Text(title)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                accessory()
            }
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                SpectrumProgressBar(progress: progress)
            }
        case .notDownloaded:
            HStack(spacing: Spacing.s) {
                StatusDot(color: Palette.inkTertiary)
                Text("Not downloaded")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Download") { Task { await model.models.prepare() } }
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
                    .help("Download \(status.engineName) (\(status.engineDownloadSize))")
            }
        case .failed(let message):
            HStack(spacing: Spacing.s) {
                StatusDot(color: Palette.danger)
                Text("Model didn't load")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .help(message)
                Spacer(minLength: 0)
                Button("Try Again") { Task { await model.models.prepare() } }
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
            }
        }
    }
}
