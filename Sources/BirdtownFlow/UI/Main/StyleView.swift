import MurmurDictionary
import MurmurKit
import SwiftUI

/// Style: how dictated text is shaped for each kind of app. Every preview is the real
/// pipeline run on the same spoken sentence, so what you pick is what you get.
struct StyleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                PageHeader(
                    "Style",
                    subtitle: "Birdtown Flow matches how you write in each kind of app. Pick a style for each."
                )
                ForEach(AppCategory.allCases) { category in
                    CategoryStyleCard(category: category, selected: settings.style(for: category)) { style in
                        settings.setStyle(style, for: category)
                    }
                }
                polishNote(provider: settings.polishProvider)
            }
            .pageLayout()
        }
    }

    private func polishNote(provider: PolishProvider) -> some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: "sparkles")
                .font(Typography.bodyEmphasis)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: Layout.Main.bannerIcon, height: Layout.Main.bannerIcon)
                .background(Circle().fill(Palette.sunken))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(provider == .off ? "AI polish is off" : "AI polish is on · \(provider.title)")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                Text("With AI polish on, your style also shapes tone and word choice, not just capitals and punctuation.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.m)
            SettingsLink {
                Text("Open Settings")
            }
            .buttonStyle(.flowSecondary)
            .controlSize(.small)
        }
        .padding(Spacing.l)
        .cardSurface(radius: Radius.m)
    }
}

private struct CategoryStyleCard: View {
    let category: AppCategory
    let selected: WritingStyle
    let onSelect: (WritingStyle) -> Void

    var body: some View {
        Card(padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: category.symbol)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: Layout.Main.categoryIcon, height: Layout.Main.categoryIcon)
                        .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(Palette.sunken))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(category.title)
                            .font(Typography.title)
                            .tracking(Tracking.title)
                            .foregroundStyle(Palette.ink)
                        Text(category.examples)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)],
                    spacing: Spacing.m
                ) {
                    ForEach(WritingStyle.allCases) { style in
                        StyleBubble(
                            style: style,
                            sample: StyleSample.preview(for: category, style: style),
                            isSelected: style == selected
                        ) {
                            onSelect(style)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(category.title)
    }
}

/// One style, shown as the message it would produce.
private struct StyleBubble: View {
    let style: WritingStyle
    let sample: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    Text(style.title)
                        .font(Typography.headline)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: Spacing.s)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(isSelected ? Palette.accent : Palette.hairlineStrong)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(sample)
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(Spacing.xxs)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: Radius.l,
                            bottomLeadingRadius: Radius.xs,
                            bottomTrailingRadius: Radius.l,
                            topTrailingRadius: Radius.l,
                            style: .continuous
                        )
                        .fill(Palette.sunken)
                    )
                Text(style.summary)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, minHeight: Layout.Main.styleBubbleMinHeight, alignment: .topLeading)
            // Chosen: Signal blue ring over a soft blue wash, like every selected card.
            .background {
                ZStack {
                    frame.fill(isHovered && !isSelected ? Palette.surfaceHover : Palette.surface)
                    if isSelected { frame.fill(Palette.accentSoft) }
                }
            }
            .overlay(frame.strokeBorder(
                isSelected ? Palette.accent : Palette.hairline,
                lineWidth: isSelected ? Layout.Main.selectionRing : Layout.Main.hairline
            ))
            .contentShape(frame)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: isSelected)
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel("\(style.title). \(sample)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// What the engine hands the pipeline for each category's previews. Parakeet returns
/// punctuated, capitalised text, so the samples look like that: one sentence of at most
/// `TextPipeline.casualPeriodWordLimit` words, ending in a full stop, with an "I" or a name
/// to lowercase and an acronym or two that very casual keeps. That way every style shows its
/// rule: formal keeps the period, casual drops it, very casual lowercases, excited exclaims.
enum StyleSample {
    static func spoken(for category: AppCategory) -> String {
        switch category {
        case .personal:
            "Just landed, I'll grab a cab and see you at home in an hour."
        case .work:
            "The API deploy is out and the dashboards look healthy, so I'm logging off."
        case .email:
            "Thanks for the contract, Sarah, and I'll have notes back to you by Friday."
        case .other:
            "Remember to renew the domain and update the DNS records before Friday."
        }
    }

    static func preview(for category: AppCategory, style: WritingStyle) -> String {
        TextPipeline.finalize(
            TextPipeline.prepare(spoken(for: category)),
            style: style,
            corrector: DictionaryCorrector(entries: []),
            snippets: []
        ).text
    }
}
