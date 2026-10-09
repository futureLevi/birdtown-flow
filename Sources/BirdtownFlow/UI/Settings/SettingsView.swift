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
        case .audio: "waveform"
        case .text: "text.quote"
        case .privacy: "lock"
        case .about: "info.circle"
        }
    }

    /// The sections that change how dictation works; About sits apart, under a hairline.
    static let preferences: [SettingsTab] = [.general, .audio, .text, .privacy]
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
                    .padding(Spacing.xxl)
            }
            .transition(.opacity)
        }
    }
}

/// The Settings card: a column of sections on the left, the chosen section's grouped rows on
/// the right, each section titled at the top of its pane.
struct SettingsView: View {
    let tab: SettingsTab
    @Environment(AppModel.self) private var model

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        HStack(spacing: 0) {
            SettingsSidebar(selection: tab) { model.settingsTab = $0 }
                .frame(width: Layout.SettingsModal.sidebarWidth)
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: Layout.Setup.hairline)
            pane(for: tab)
                .id(tab)
                // About opens on the app's name; a heading above it would say less.
                .environment(\.settingsPaneTitle, tab == .about ? nil : tab.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    IconButton(symbol: "xmark", label: "Close Settings (Esc)") { model.closeSettings() }
                        .padding(Spacing.m)
                }
        }
        .frame(maxWidth: Layout.SettingsModal.size.width, maxHeight: Layout.SettingsModal.size.height)
        .background(Palette.canvas)
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

/// The card's left column: the sections, then the version at the foot.
private struct SettingsSidebar: View {
    let selection: SettingsTab
    let select: (SettingsTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Settings")
                .eyebrowStyle()
                .padding(.horizontal, Spacing.s)
                .padding(.bottom, Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(SettingsTab.preferences) { tab in
                SettingsSidebarRow(tab: tab, isSelected: tab == selection) { select(tab) }
            }
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: Layout.Setup.hairline)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.s)
            SettingsSidebarRow(tab: .about, isSelected: selection == .about) { select(.about) }
            Spacer(minLength: Spacing.l)
            Text(AppVersion.display)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
                .lineLimit(1)
                .padding(.horizontal, Spacing.s)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sunken)
    }
}

/// One section in the card's left column: icon and name, a Signal blue wash when chosen.
private struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: tab.symbol)
                    .font(Typography.body)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.inkSecondary)
                    .frame(width: Layout.iconMedium)
                Text(tab.title)
                    .font(isSelected ? Typography.bodyEmphasis : Typography.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Layout.SettingsModal.rowHeight, alignment: .leading)
            .background(shape.fill(isSelected ? Palette.accentSoft : (isHovered ? Palette.surfaceHover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
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
}

extension EnvironmentValues {
    /// The heading a Settings pane shows above its groups: the section's name in the modal,
    /// `nil` (no heading) where the pane is shown on its own.
    @Entry var settingsPaneTitle: String? = nil
}

// MARK: - Building blocks

/// A pane: warm canvas, the section's title, then groups stacked with generous rhythm,
/// scrolling inside whatever height the Settings card has.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.settingsPaneTitle) private var title
    /// Width the pane's scroll view takes, and the width its content gets inside it. With a
    /// legacy (always visible) scroller the content is narrower by the scroller's gutter.
    @State private var paneWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    /// The legacy scroller's gutter, when there is one: taken out of the trailing margin so
    /// cards keep the same width and edges on every tab, scrolling or not.
    private var scrollerGutter: CGFloat {
        guard paneWidth > 0, contentWidth > 0 else { return 0 }
        return min(max(paneWidth - contentWidth, 0), Spacing.xxl)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if let title {
                    Text(title)
                        .font(Typography.title)
                        .tracking(Tracking.title)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                content
            }
            .padding(.vertical, Spacing.xxl)
            .padding(.leading, Spacing.xxl)
            .padding(.trailing, Spacing.xxl - scrollerGutter)
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
        .background(Palette.canvas)
        .tint(Palette.accent)
    }
}

/// A titled card of rows. Rows are separated with `SettingsDivider()`.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let title {
                Text(title)
                    .eyebrowStyle()
                    .padding(.leading, Spacing.xs)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Palette.hairline))
            if let footnote {
                Text(footnote)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }
}

/// Label and one-line explanation on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .frame(minHeight: Layout.rowMinHeight)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: Layout.Setup.hairline)
            .padding(.leading, Spacing.l)
    }
}

/// A switch with its label hidden, since the row already says what it does.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}
