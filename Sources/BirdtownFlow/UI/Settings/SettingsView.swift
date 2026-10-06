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
}

/// The Settings window (⌘,): toolbar tabs, each a column of grouped rows.
struct SettingsView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { tab in
                pane(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .frame(width: Layout.settingsWidth)
        // Settings is its own window, outside the main window's tint: switches, pickers and
        // steppers take Signal blue here too rather than the system accent.
        .tint(Palette.accent)
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

// MARK: - Building blocks

/// A pane: warm canvas, groups stacked with generous rhythm, scrolling inside a fixed height.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                content
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Layout.settingsWidth, height: Layout.Setup.settingsHeight)
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
