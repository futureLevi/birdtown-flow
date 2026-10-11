import AppKit
import Combine
import MurmurKit
import SwiftUI

/// The main window: a flush grey sidebar of sections and a quiet detail column.
///
/// Laid out by hand rather than with `NavigationSplitView`, whose macOS 26 sidebar is a
/// floating glass panel: Mono v2's sidebar is a flat step off the canvas, running from the top
/// of the window (under the traffic lights) to the bottom.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = preview.status ?? SystemStatus.live(model)
        let settingsOpen = model.settingsTab != nil
        let sidebarHidden = model.sidebarHidden
        HStack(spacing: 0) {
            if !sidebarHidden {
                MainSidebar()
                    .frame(width: Layout.Sidebar.width)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            ZStack {
                page(status: status)
                    .id(model.section)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // With the sidebar away, the page starts below the traffic lights.
            .padding(.top, sidebarHidden ? Layout.Sidebar.collapsedTopInset : 0)
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

/// The app icon and name, at the top of the sidebar above Home.
struct SidebarWordmark: View {
    var body: some View {
        HStack(spacing: Layout.Sidebar.rowSpacing) {
            // The artwork keeps the standard icon margin; its tile fills the 28 pt slot.
            AppIconArtwork(size: Layout.Main.sidebarLogo, showsShadow: false)
                .frame(width: Layout.Sidebar.wordmarkHeight, height: Layout.Sidebar.wordmarkHeight)
            Text("Birdtown Flow")
                .font(Typography.wordmark)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
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

extension SidebarSection {
    /// The section's icon colour: the sidebar walks the logo's colour wheel from the top.
    var tint: Color {
        switch self {
        case .home: Palette.Wheel.orange
        case .history: Palette.Wheel.gold
        case .dictionary: Palette.Wheel.green
        case .snippets: Palette.Wheel.cyan
        case .style: Palette.Wheel.blue
        case .lab: Palette.Wheel.violet
        }
    }
}

/// The wordmark, the sections, then Settings at the foot. Nothing under Settings: whether the
/// shortcut and the model are ready is in Settings, and anything that needs fixing is a banner
/// on Home.
struct MainSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Cached in the store; a failed record waiting out a delete's undo window doesn't
        // count. Only the few pending ids are looked up, and only while a delete is pending.
        let pending = model.historyDeletion.pending
        let failed = model.history.failedCount - (pending.isEmpty ? 0 : pending.reduce(0) { count, id in
            count + (model.history.record(id: id)?.outcome == .failed ? 1 : 0)
        })
        VStack(alignment: .leading, spacing: 0) {
            SidebarWordmark()
                .frame(height: Layout.Sidebar.wordmarkHeight)
                .padding(.horizontal, Layout.Sidebar.rowPadding)
                .padding(.bottom, Layout.Sidebar.wordmarkBottom)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SidebarSection.everyday) { section in
                        row(section, count: section == .history ? failed : 0)
                    }
                    Text("Admin")
                        .font(Typography.sidebarLabel)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, Layout.Sidebar.rowPadding)
                        .padding(.top, Layout.Sidebar.labelTop)
                        .padding(.bottom, Layout.Sidebar.labelBottom)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(SidebarSection.admin) { section in
                        row(section)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            SidebarSettingsButton()
        }
        .padding(.top, Layout.Sidebar.topInset)
        .padding(.horizontal, Layout.Sidebar.horizontalPadding)
        .padding(.bottom, Layout.Sidebar.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar)
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
            tint: section.tint,
            count: count,
            countLabel: count == 1 ? "1 failed" : "\(count) failed",
            isSelected: model.section == section
        ) {
            // Arrow keys and clicks can't reach the page behind the Settings modal.
            if model.settingsTab == nil { model.section = section }
        }
    }
}

/// One row of the sidebar: a coloured icon, the name, and a count when there is one. The
/// chosen row takes a grey fill; colour stays on the icons.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let tint: Color
    var count = 0
    var countLabel = ""
    var isSelected = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.Sidebar.rowRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: Layout.Sidebar.rowSpacing) {
                Image(systemName: symbol)
                    .font(Typography.sidebarIcon)
                    .foregroundStyle(tint)
                    .frame(width: Layout.Sidebar.iconColumn)
                    .accessibilityHidden(true)
                Text(title)
                    .font(isSelected ? Typography.sidebarRowSelected : Typography.sidebarRow)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if count > 0 {
                    Text(count, format: .number)
                        .font(Typography.sidebarCount)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.horizontal, Layout.Sidebar.rowPadding)
            .frame(maxWidth: .infinity, minHeight: Layout.Sidebar.rowHeight)
            .background(shape.fill(isSelected ? Palette.selection : (isHovered ? Palette.sidebarHover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
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
        SidebarRow(title: "Settings", symbol: "gearshape", tint: Palette.Wheel.purple) {
            guard preview.status == nil else { return }
            model.showSettings()
        }
        .help("Settings (⌘,)")
    }
}

/// Hide sidebar (top right of the sidebar) and Show sidebar (beside the traffic lights once
/// it's hidden). View › Toggle Sidebar (⌃⌘S) does the same.
struct SidebarToggleButton: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false
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
                .foregroundStyle(isHovered ? Palette.inkSecondary : Palette.icon)
                .frame(width: Layout.Sidebar.hideButton, height: Layout.Sidebar.hideButton)
                .background(shape.fill(isHovered ? Palette.sidebarHover : .clear))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .help("\(label) (⌃⌘S)")
        .accessibilityLabel(label)
    }
}
