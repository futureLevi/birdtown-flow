import MurmurKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case audio
    case text
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .audio: "Audio & Speech"
        case .text: "Text & AI"
        case .privacy: "Privacy & History"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .audio: "speaker.wave.2"
        case .text: "sparkles"
        case .privacy: "lock"
        case .about: "info.circle"
        }
    }
}

/// Settings as a modal over the main window, dimming everything behind it. Open it with
/// `AppModel.showSettings(_:)` (⌘,, the sidebar's Settings row, the menu bar); Esc, a click
/// outside the card or its close button dismiss it through `AppModel.closeSettings()`.
struct SettingsOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let tab = model.settingsTab {
            ZStack {
                Palette.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeSettings() }
                    .accessibilityHidden(true)
                SettingsView(tab: tab)
                    .padding(Layout.SettingsModal.margin)
            }
            .transition(.opacity)
        }
    }
}

/// The Settings card: a quiet rail of sections on the left; on the right the chosen section's
/// title and close button over a hairline, then its rows.
struct SettingsView: View {
    let tab: SettingsTab
    @Environment(AppModel.self) private var model

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        HStack(spacing: 0) {
            SettingsSidebar(selection: tab) { model.settingsTab = $0 }
                .frame(width: Layout.SettingsModal.sidebarWidth)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: Layout.Setup.hairline)
                }
            VStack(spacing: 0) {
                header
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: Layout.Setup.hairline)
                pane(for: tab)
                    .id(tab)
                    // The header above names the section; the pane doesn't repeat it.
                    .environment(\.settingsPaneTitle, nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: Layout.SettingsModal.size.width, maxHeight: Layout.SettingsModal.size.height)
        .background(Palette.surface)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.hairline, lineWidth: Layout.Setup.hairline))
        .shadow(color: Elevation.modal.color, radius: Elevation.modal.radius, y: Elevation.modal.y)
        // Settings sits inside the main window, so it already takes Signal blue for switches,
        // pickers and steppers; set here too so the card is right wherever it's hosted.
        .tint(Palette.accent)
        .background { CloseOnEscape { model.closeSettings() } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Settings")
    }

    private var header: some View {
        HStack(spacing: Spacing.l) {
            Text(tab.title)
                .font(Typography.paneTitle)
                .tracking(Tracking.title)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.l)
            IconButton(symbol: "xmark", label: "Close Settings (Esc)") { model.closeSettings() }
        }
        .padding(.leading, Layout.SettingsRail.panePadding)
        .padding(.trailing, Spacing.xl)
        .frame(height: Layout.SettingsRail.headerHeight)
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsPane()
        case .audio: AudioSettingsPane()
        case .text: TextSettingsPane()
        case .privacy: PrivacySettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}

/// Esc closes Settings, as it would a sheet. An invisible button, so the key works without
/// a visible control; the shortcut recorder swallows its own Esc before this sees it.
private struct CloseOnEscape: View {
    let action: () -> Void

    var body: some View {
        Button("Close Settings", action: action)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

/// The card's left column: the five sections in a stable order, then the app and its version
/// at the foot.
private struct SettingsSidebar: View {
    let selection: SettingsTab
    let select: (SettingsTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.SettingsRail.rowGap) {
            Text("Settings")
                .font(Typography.settingsRailTitle)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, Layout.SettingsRail.rowPadding)
                .padding(.bottom, Layout.SettingsRail.titleBottom)
                .accessibilityAddTraits(.isHeader)
            ForEach(SettingsTab.allCases) { tab in
                SettingsSidebarRow(tab: tab, isSelected: tab == selection) { select(tab) }
            }
            Spacer(minLength: Layout.SettingsRail.footerTop)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Birdtown Flow")
                Text(AppVersion.display)
                    .textSelection(.enabled)
            }
            .font(Typography.callout)
            .foregroundStyle(Palette.inkSecondary)
            .lineLimit(1)
            .padding(.horizontal, Layout.SettingsRail.rowPadding)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Layout.SettingsRail.sidePadding)
        .padding(.top, Layout.SettingsRail.topPadding)
        .padding(.bottom, Layout.SettingsRail.bottomPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar)
    }
}

/// One section in the card's left column. Chosen: Signal blue tint, a blue edge, accent text and
/// icon in a heavier weight, and the selected trait for VoiceOver, so it never rests on hue alone.
private struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.SettingsRail.rowRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: Layout.Sidebar.rowSpacing) {
                Image(systemName: tab.symbol)
                    .font(isSelected ? Typography.sidebarIconSelected : Typography.sidebarIcon)
                    .foregroundStyle(isSelected ? Palette.accentInk : Palette.inkSecondary)
                    .frame(width: Layout.SettingsRail.iconColumn)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(isSelected ? Typography.sidebarRowSelected : Typography.sidebarRow)
                    .foregroundStyle(isSelected ? Palette.accentInk : Palette.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, Layout.SettingsRail.rowPadding)
            .frame(maxWidth: .infinity, minHeight: Layout.SettingsRail.rowHeight, alignment: .leading)
            .background(shape.fill(isSelected ? Palette.selection : (isHovered ? Palette.sidebarHover : .clear)))
            .overlay(shape.strokeBorder(isSelected ? Palette.accentEdge : .clear, lineWidth: Layout.Setup.hairline))
            .contentShape(shape)
            .flowFocusRing(shape, drawn: isFocused)
        }
        .buttonStyle(.plain)
        // The label draws the 3 pt focus ring in the row's own shape.
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The version people quote in a bug report: "Version 1.2 (345)", or "Development build" when
/// run outside an app bundle.
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        if let build = info?["CFBundleVersion"] as? String, build != short {
            return "Version \(short) (\(build))"
        }
        return "Version \(short)"
    }

    /// The commit the build was made from, which `make app` writes into Info.plist, so a
    /// nightly can be told from the next one. `nil` outside a bundle built that way.
    static var commit: String? {
        Bundle.main.infoDictionary?["BirdtownCommit"] as? String
    }
}

extension EnvironmentValues {
    /// The heading a Settings pane shows above its groups: the section's name in the modal,
    /// `nil` (no heading) where the pane is shown on its own.
    @Entry var settingsPaneTitle: String? = nil
}

// MARK: - Building blocks

/// A pane: the surface, then groups of flat rows, scrolling inside whatever height the Settings
/// card has. Shown on its own (snapshots), it carries the section's title at the top.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.settingsPaneTitle) private var title
    /// Width the pane's scroll view takes, and the width its content gets inside it. With a
    /// legacy (always visible) scroller the content is narrower by the scroller's gutter.
    @State private var paneWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    /// The legacy scroller's gutter, when there is one: taken out of the trailing margin so
    /// rows keep the same width and edges on every tab, scrolling or not.
    private var scrollerGutter: CGFloat {
        guard paneWidth > 0, contentWidth > 0 else { return 0 }
        return min(max(paneWidth - contentWidth, 0), Layout.SettingsRail.panePadding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if let title {
                    Text(title)
                        .font(Typography.paneTitle)
                        .tracking(Tracking.title)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, Spacing.l)
                        .accessibilityAddTraits(.isHeader)
                }
                content
            }
            .padding(.top, Layout.SettingsRail.paneTop)
            .padding(.bottom, Spacing.xxxl)
            .padding(.leading, Layout.SettingsRail.panePadding)
            .padding(.trailing, Layout.SettingsRail.panePadding - scrollerGutter)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                contentWidth = width
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            paneWidth = width
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .tint(Palette.accent)
    }
}

/// A titled run of flat rows on the pane: no card, hairlines between rows. Rows are separated
/// with `SettingsDivider()`.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.SettingsRail.groupTitleGap) {
            if let title {
                SettingsGroupTitle(text: title)
            }
            VStack(spacing: 0) { content }
            if let footnote {
                Text(footnote)
                    .font(Typography.settingsRowDetail)
                    .lineSpacing(Layout.SettingsRail.detailLineSpacing)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Layout.SettingsRail.groupTop - Spacing.s)
    }
}

/// A group's title: quiet, in the secondary ink, so the rows' own titles lead.
struct SettingsGroupTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.headline)
            .foregroundStyle(Palette.inkSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Label and one-line explanation on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Layout.SettingsRail.controlGap) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.settingsRowTitle)
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail)
                        .font(Typography.settingsRowDetail)
                        .lineSpacing(Layout.SettingsRail.detailLineSpacing)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, Layout.SettingsRail.rowInset)
        .padding(.vertical, Layout.SettingsRail.rowVertical)
        .frame(minHeight: Layout.rowMinHeight)
        .accessibilityElement(children: .contain)
    }
}

/// The hairline between two rows of a group, as wide as the rows.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: Layout.Setup.hairline)
            .padding(.leading, Layout.SettingsRail.rowInset)
    }
}

/// A switch with its label hidden, since the row already says what it does. The label still
/// reaches VoiceOver, with the switch's on/off state.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Palette.accent)
            .accessibilityLabel(label)
    }
}

/// A pane's secondary button: the outlined 15 pt button at the handoff's 35 pt height.
extension View {
    func settingsButton() -> some View {
        buttonStyle(.flowSecondary)
            .controlSize(.small)
    }
}

/// A notice inside a pane: an icon and a sentence on a tinted well, at the pane's reading size.
struct SettingsNotice: View {
    let symbol: String
    let tint: Color
    let fill: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(Typography.callout)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(fill))
        .accessibilityElement(children: .combine)
    }
}

/// A refused or cautioned shortcut, explained under the row that recorded it.
struct SettingsShortcutNotice: View {
    let verdict: ShortcutVerdict

    var body: some View {
        switch verdict {
        case .accepted:
            EmptyView()
        case .caution(let message):
            SettingsNotice(
                symbol: "exclamationmark.triangle.fill",
                tint: Palette.warning,
                fill: Palette.warningSoft,
                text: message
            )
        case .rejected(let message):
            SettingsNotice(
                symbol: "xmark.octagon.fill",
                tint: Palette.danger,
                fill: Palette.dangerSoft,
                text: "Not changed. \(message)"
            )
        }
    }
}
