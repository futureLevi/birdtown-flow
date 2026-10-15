import SwiftUI

/// The label above a group of rows, with an optional count or detail and a trailing accessory.
///
/// `.section` is a page section's title ("Recent dictation": 21 pt); `.group` is a smaller
/// heading inside one, like History's day labels (16 pt).
struct SectionHeader<Trailing: View>: View {
    enum Level { case section, group }

    let title: String
    var detail: String?
    var level: Level = .group
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Text(title)
                .font(level == .section ? Typography.title : Typography.headline)
                .tracking(level == .section ? Tracking.title : 0)
                .foregroundStyle(Palette.ink)
            if let detail {
                Text(detail)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: Spacing.s)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil, level: Level = .group) {
        self.init(title: title, detail: detail, level: level) { EmptyView() }
    }
}

/// A page's title block: the 34 pt page title, a 17 pt description, actions on the right. An
/// optional symbol tile (a Signal blue, violet or teal wash) sits before the title.
struct PageHeader<Actions: View>: View {
    /// The symbol tile's colour: Signal blue by default, violet for tuning (Lab), teal for
    /// vocabulary (Dictionary).
    enum Tone { case accent, violet, teal }

    let title: String
    var subtitle: String?
    var symbol: String?
    var tone: Tone
    let actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        tone: Tone = .accent,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tone = tone
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xl) {
            HStack(alignment: .center, spacing: Layout.Main.pageHeaderSymbolGap) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(Typography.pageSymbol)
                        .foregroundStyle(foreground)
                        .frame(width: Layout.Main.pageHeaderSymbol, height: Layout.Main.pageHeaderSymbol)
                        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(soft))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(Typography.display)
                        .tracking(Tracking.display)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(Typography.bodyLarge)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: Layout.Main.pageSubtitleWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: Spacing.l)
            actions
        }
    }

    private var foreground: Color {
        switch tone {
        case .accent: Palette.accent
        case .violet: Palette.violet
        case .teal: Palette.teal
        }
    }

    private var soft: Color {
        switch tone {
        case .accent: Palette.accentSoft
        case .violet: Palette.violetSoft
        case .teal: Palette.tealSoft
        }
    }
}

extension PageHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tone: Tone = .accent) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tone: tone) { EmptyView() }
    }
}
