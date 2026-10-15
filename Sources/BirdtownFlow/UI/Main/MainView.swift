import AppKit
import Combine
import MurmurKit
import SwiftUI

/// The main window: a flush 234 pt sidebar, a 66 pt toolbar and a quiet detail column.
///
/// Laid out by hand rather than with `NavigationSplitView`, whose macOS 26 sidebar is a
/// floating glass panel: the sidebar here is flat, a gentle wash off the canvas, and runs from
/// the top of the window (under the traffic lights) to the bottom.
///
/// The toolbar floats over the top of the detail column. Every page except Home is inset
/// below it (`Layout.Toolbar.height`). Home starts at the window's top, so its open-canvas art
/// can sit behind the toolbar, and insets its own content.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = preview.status ?? SystemStatus.live(model)
        let settingsOpen = model.settingsTab != nil
        let sidebarHidden = model.sidebarHidden
        let opensOnCanvas = model.section == .home
        HStack(spacing: 0) {
            if !sidebarHidden {
                MainSidebar()
                    .frame(width: Layout.Sidebar.width)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            ZStack(alignment: .top) {
                ZStack {
                    page(status: status)
                        .id(model.section)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, opensOnCanvas ? 0 : Layout.Toolbar.height)
                MainToolbar(status: status, isOverCanvas: opensOnCanvas)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
            .overlay(alignment: .topLeading) {
                if sidebarHidden {
                    SidebarToggleButton()
                        .padding(.leading, Layout.Sidebar.showButtonLeading)
                        .padding(.top, Layout.Sidebar.hideButtonTop)
                }
            }
            // Pages cross-fade; the window never slides.
            .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: model.section)
        }
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: sidebarHidden)
        // No title bar: the sidebar runs up under the traffic lights and pages start at the
        // top of the window, as they do in snapshots.
        .ignoresSafeArea(.container, edges: .top)
        // Signal blue for every system control: toggles, focus rings.
        .tint(Palette.accent)
        .background(Palette.canvas)
        .background { SectionShortcuts() }
        // Settings is modal: nothing behind it takes clicks, keys or focus while it's open.
        .disabled(settingsOpen)
        .accessibilityHidden(settingsOpen)
        .overlay {
            SettingsOverlay()
                .animation(Motion.resolve(Motion.fade, reduceMotion: reduceMotion), value: settingsOpen)
        }
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
            HistoryView(
                initialQuery: preview.historyQuery,
                originalRecordID: preview.originalRecordID,
                initialSelection: preview.historySelection
            )
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

// MARK: - Toolbar

/// How the toolbar's status dot is coloured. The label always says the same thing in words.
enum ToolbarStatusTone {
    case ready, warning, danger

    var color: Color {
        switch self {
        case .ready: Palette.success
        case .warning: Palette.warning
        case .danger: Palette.danger
        }
    }
}

extension SystemStatus {
    /// The toolbar's one-line answer to "will dictation work right now?".
    var toolbarSummary: (label: String, tone: ToolbarStatusTone) {
        if !microphone { return ("Microphone off", .danger) }
        if !accessibility { return ("Accessibility off", .warning) }
        if !hotkeyActive { return ("Shortcut paused", .warning) }
        switch model {
        case .ready: return ("Ready to dictate", .ready)
        case .loading: return ("Loading speech model", .warning)
        case .downloading: return ("Downloading speech model", .warning)
        case .notDownloaded: return ("Speech model needed", .warning)
        case .failed: return ("Speech model failed", .danger)
        }
    }
}

/// The 66 pt toolbar: the page's name on the left; Search history and whether dictation is
/// ready on the right. Over Home it's transparent, so the hero art shows through.
struct MainToolbar: View {
    let status: SystemStatus
    var isOverCanvas = false

    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = status.toolbarSummary
        HStack(spacing: Layout.Toolbar.gap) {
            Text(model.section.title)
                .font(Typography.toolbarTitle)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: Spacing.l)
            ToolbarSearchButton { model.showHistorySearch() }
            HStack(spacing: Layout.Toolbar.itemSpacing) {
                StatusDot(color: summary.tone.color)
                Text(summary.label)
                    .font(Typography.toolbarItem)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status")
            .accessibilityValue(summary.label)
        }
        .padding(.leading, model.sidebarHidden ? Layout.Toolbar.hiddenLeading : Layout.Toolbar.inset)
        .padding(.trailing, Layout.Toolbar.inset)
        .frame(height: Layout.Toolbar.height)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                if !isOverCanvas { Palette.toolbar }
                // Empty toolbar space moves the window, as a title bar would.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
            }
        }
        .overlay(alignment: .bottom) {
            if !isOverCanvas {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: Layout.Main.hairline)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Search history" in the toolbar: magnifier and label, quiet until hovered.
private struct ToolbarSearchButton: View {
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        Button(action: action) {
            HStack(spacing: Layout.Toolbar.itemSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.toolbarItem)
                    .accessibilityHidden(true)
                Text("Search history")
                    .font(Typography.toolbarItem)
                    .lineLimit(1)
            }
            .foregroundStyle(isHovered ? Palette.ink : Palette.inkSecondary)
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: Layout.Main.buttonHeightSmall)
            .contentShape(shape)
            .flowFocusRing(shape, drawn: isFocused)
        }
        .buttonStyle(.plain)
        // The ring above is the focus indicator; the system's would double it.
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .help("Search history")
    }
}

// MARK: - Sidebar

/// The app icon and name, at the top of the sidebar above Home.
struct SidebarWordmark: View {
    var body: some View {
        HStack(spacing: Layout.Sidebar.wordmarkSpacing) {
            // The real app icon: the artwork keeps the standard icon margin around its tile.
            AppIconArtwork(size: Layout.Sidebar.logo, showsShadow: false)
                .frame(width: Layout.Sidebar.logo, height: Layout.Sidebar.logo)
            Text("Birdtown Flow")
                .font(Typography.wordmark)
                .tracking(Tracking.title)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Birdtown Flow")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The wordmark, Home to Style, a divider and "Workspace" with the Lab, then Settings and the
/// shortcut hint at the foot. Whether the shortcut and the model are ready is the toolbar's
/// status, and anything that needs fixing is a banner on Home.
struct MainSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview

    var body: some View {
        // Cached in the store; a failed record waiting out a delete's undo window doesn't
        // count. Only the few pending ids are looked up, and only while a delete is pending.
        let pending = model.historyDeletion.pending
        let failed = model.history.failedCount - (pending.isEmpty ? 0 : pending.reduce(0) { count, id in
            count + (model.history.record(id: id)?.outcome == .failed ? 1 : 0)
        })
        let shortcut = preview.status?.pushToTalkKey ?? model.settings.pushToTalkKey.displayName
        VStack(alignment: .leading, spacing: 0) {
            // The traffic lights' row. Its drag strip and the Hide sidebar button are overlays.
            Color.clear.frame(height: Layout.Sidebar.topInset)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarWordmark()
                        .padding(.leading, Layout.Sidebar.wordmarkInset)
                        .padding(.bottom, Layout.Sidebar.wordmarkBottom)
                    VStack(alignment: .leading, spacing: Layout.Sidebar.rowGap) {
                        ForEach(SidebarSection.everyday) { section in
                            row(section, count: section == .history ? failed : 0)
                        }
                    }
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: Layout.Main.hairline)
                        .padding(.horizontal, Layout.Sidebar.dividerInset)
                        .padding(.vertical, Layout.Sidebar.dividerVertical)
                        .accessibilityHidden(true)
                    Text("Workspace")
                        .font(Typography.sidebarLabel)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, Layout.Sidebar.rowPadding)
                        .padding(.bottom, Layout.Sidebar.labelBottom)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: Layout.Sidebar.rowGap) {
                        ForEach(SidebarSection.admin) { section in
                            row(section)
                        }
                    }
                }
                .padding(.horizontal, Layout.Sidebar.horizontalPadding)
                // Room for the focus ring above the first row.
                .padding(.top, Spacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            VStack(alignment: .leading, spacing: 0) {
                SidebarSettingsButton()
                SidebarShortcutHint(key: shortcut)
            }
            .padding(.horizontal, Layout.Sidebar.horizontalPadding)
            .padding(.bottom, Layout.Sidebar.bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                stops: Palette.sidebarGradient,
                startPoint: Palette.sidebarGradientStart,
                endPoint: Palette.sidebarGradientEnd
            )
        )
        // The hairline between the sidebar and the page.
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: Layout.Main.hairline)
        }
        // The strip under the traffic lights moves the window, as a title bar would.
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: Layout.Sidebar.topInset)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
        .overlay(alignment: .topTrailing) {
            SidebarToggleButton()
                .padding(.top, Layout.Sidebar.hideButtonTop)
                .padding(.trailing, Layout.Sidebar.hideButtonTrailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }

    private func row(_ section: SidebarSection, count: Int = 0) -> some View {
        SidebarRow(
            title: section.title,
            symbol: section.symbol,
            count: count,
            countLabel: count == 1 ? "1 failed" : "\(count) failed",
            isSelected: model.section == section
        ) {
            // Arrow keys and clicks can't reach the page behind the Settings modal.
            if model.settingsTab == nil { model.section = section }
        }
    }
}

/// One row of the sidebar: a monochrome icon, the name, and a count when there is one. The
/// chosen row takes Signal blue's tint, blue text, a heavier weight and a marker bar in the
/// margin, so it never rests on hue alone.
struct SidebarRow: View {
    let title: String
    let symbol: String
    var count = 0
    var countLabel = ""
    var isSelected = false
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.Sidebar.rowRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: Layout.Sidebar.rowSpacing) {
                Image(systemName: symbol)
                    .font(isSelected ? Typography.sidebarIconSelected : Typography.sidebarIcon)
                    .frame(width: Layout.Sidebar.iconColumn)
                    .accessibilityHidden(true)
                Text(title)
                    .font(isSelected ? Typography.sidebarRowSelected : Typography.sidebarRow)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if count > 0 {
                    Text(count, format: .number)
                        .font(Typography.sidebarCount)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .foregroundStyle(isSelected ? Palette.accentInk : (isHovered ? Palette.ink : Palette.inkSecondary))
            .padding(.horizontal, Layout.Sidebar.rowPadding)
            .frame(maxWidth: .infinity, minHeight: Layout.Sidebar.rowHeight)
            .background(shape.fill(isSelected ? Palette.selection : (isHovered ? Palette.sidebarHover : .clear)))
            .overlay(shape.strokeBorder(isSelected ? Palette.accentEdge : .clear, lineWidth: Layout.Main.hairline))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: Layout.Sidebar.markerWidth)
                        .padding(.vertical, Layout.Sidebar.markerInset)
                        .offset(x: -Layout.Sidebar.markerOffset)
                }
            }
            .contentShape(shape)
            .flowFocusRing(shape, drawn: isFocused)
        }
        .buttonStyle(.plain)
        // The ring above is the focus indicator; the system's would double it.
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? countLabel : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Settings, at the foot of the sidebar: opens the Settings modal over the window (⌘,).
struct SidebarSettingsButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview

    var body: some View {
        SidebarRow(title: "Settings", symbol: "gearshape") {
            guard preview.status == nil else { return }
            model.showSettings()
        }
        .help("Settings (⌘,)")
    }
}

/// "fn  Hold to dictate": the push-to-talk key as the user has set it, under Settings.
private struct SidebarShortcutHint: View {
    let key: String

    var body: some View {
        HStack(spacing: Layout.Sidebar.hintSpacing) {
            KeyCap(label: key)
            Text("Hold to dictate")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Layout.Sidebar.hintInset)
        .padding(.top, Layout.Sidebar.hintTop)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold \(key) to dictate")
    }
}

/// Hide sidebar (top right of the sidebar) and Show sidebar (beside the traffic lights once
/// it's hidden). View › Toggle Sidebar (⌃⌘S) does the same.
struct SidebarToggleButton: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hidden = model.sidebarHidden
        let label = hidden ? "Show sidebar" : "Hide sidebar"
        let shape = RoundedRectangle(cornerRadius: Layout.Sidebar.hideButtonRadius, style: .continuous)
        Button {
            model.sidebarHidden.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(Typography.sidebarIcon)
                .foregroundStyle(isHovered ? Palette.accentInk : Palette.icon)
                .frame(width: Layout.Sidebar.hideButton, height: Layout.Sidebar.hideButton)
                .background(shape.fill(isHovered ? Palette.accentSoft : .clear))
                .contentShape(shape)
                .flowFocusRing(shape, drawn: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .help("\(label) (⌃⌘S)")
        .accessibilityLabel(label)
    }
}
