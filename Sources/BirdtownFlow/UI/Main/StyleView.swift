import MurmurDictionary
import MurmurKit
import SwiftUI

/// Style: how dictated text is shaped for each kind of app. The app categories are listed on
/// the left; on the right one tone is chosen for the selected category, with one live example.
/// The example is the real pipeline run on a spoken sentence, so what you pick is what you get.
struct StyleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selected: AppCategory = .personal
    /// The last choice that was written and read back; nil until the person changes one.
    @State private var saved: SavedChoice?
    /// The tone grid's measured width: one column when two won't fit. 0 until measured.
    @State private var toneWidth: CGFloat = 0

    private struct SavedChoice: Equatable {
        let category: AppCategory
        let style: WritingStyle
    }

    var body: some View {
        let settings = model.settings
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                PageHeader(
                    "Style",
                    subtitle: "Still you. Just right for where you\u{2019}re writing.",
                    symbol: SidebarSection.style.symbol,
                    tone: .violet
                )
                HStack(alignment: .top, spacing: Layout.Style.columnGap) {
                    categoryList
                        .frame(width: Layout.Style.listWidth)
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        detailPanel(
                            category: selected,
                            style: settings.style(for: selected),
                            provider: settings.polishProvider
                        )
                        if let saved {
                            savedNote(saved)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .pageLayout()
        }
        .animation(Motion.resolve(Motion.fade, reduceMotion: reduceMotion), value: saved)
    }

    // MARK: - Categories

    private var categoryList: some View {
        VStack(spacing: Layout.Style.listGap) {
            ForEach(AppCategory.allCases) { category in
                CategoryRow(
                    category: category,
                    tone: model.settings.style(for: category),
                    isSelected: category == selected
                ) {
                    selected = category
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App categories")
    }

    // MARK: - Panel

    private func detailPanel(category: AppCategory, style: WritingStyle, provider: PolishProvider) -> some View {
        Card(padding: Layout.Style.panelInset) {
            VStack(alignment: .leading, spacing: 0) {
                Text(category.title)
                    .font(Typography.sectionTitle)
                    .tracking(Tracking.title)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(category.examples)
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, Layout.Style.panelSubtitleTop)
                toneChoices(category: category, selected: style)
                    .padding(.vertical, Layout.Style.toneBlockGap)
                previewSection(category: category, style: style)
                polishRow(style: style, provider: provider)
            }
        }
    }

    private func toneChoices(category: AppCategory, selected: WritingStyle) -> some View {
        let columns = toneColumns
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Layout.Style.toneGap, alignment: .top),
                count: columns
            ),
            spacing: Layout.Style.toneGap
        ) {
            ForEach(WritingStyle.allCases) { tone in
                ToneChoice(style: tone, isSelected: tone == selected) {
                    choose(tone, for: category)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            toneWidth = newWidth
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Writing tone")
    }

    private var toneColumns: Int {
        let twoAcross = Layout.Style.toneMinWidth * 2 + Layout.Style.toneGap
        return toneWidth > 0 && toneWidth < twoAcross ? 1 : 2
    }

    /// Writes the choice, then reads it back: the note only appears once Settings reports it.
    private func choose(_ style: WritingStyle, for category: AppCategory) {
        guard model.settings.style(for: category) != style else { return }
        model.settings.setStyle(style, for: category)
        guard model.settings.style(for: category) == style else {
            saved = nil
            return
        }
        saved = SavedChoice(category: category, style: style)
        AccessibilityNotification.Announcement("\(category.title) set to \(style.title)").post()
    }

    // MARK: - Preview

    private func previewSection(category: AppCategory, style: WritingStyle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                Text("A little preview")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.s)
                Text("Updates as you choose")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.bottom, Layout.Style.previewHeadBottom)
            VStack(alignment: .leading, spacing: 0) {
                speaker(symbol: "mic", tint: Palette.violet, label: "You say")
                Text("\u{201C}\(StyleSample.said(for: category))\u{201D}")
                    .font(Typography.bodyLarge)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(Spacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.Style.saidTop)
                    .padding(.bottom, Layout.Style.saidBottom)
                speaker(symbol: category.symbol, tint: Palette.violet, label: "In \(StyleSample.app(for: category))")
                outputBubble(StyleSample.preview(for: category, style: style))
                    .padding(.top, Layout.Style.bubbleTop)
            }
            .padding(Layout.Style.previewInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.Style.previewRadius, style: .continuous)
                    .fill(Palette.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.Style.previewRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline)
            )
            .accessibilityElement(children: .contain)
        }
        .padding(.top, Layout.Style.previewTop)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: Layout.Main.hairline)
        }
    }

    private func speaker(symbol: String, tint: Color, label: String) -> some View {
        HStack(spacing: Layout.Style.speakerGap) {
            Image(systemName: symbol)
                .font(Typography.callout)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(label)
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    /// The text as the app would receive it: a message bubble with a square tail corner.
    private func outputBubble(_ text: String) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Radius.l,
            bottomLeadingRadius: Radius.xs,
            bottomTrailingRadius: Radius.l,
            topTrailingRadius: Radius.l,
            style: .continuous
        )
        return Text(text)
            .font(Typography.transcriptLarge)
            .foregroundStyle(Palette.ink)
            .lineSpacing(Spacing.transcriptLine)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Layout.Style.bubbleInsetHorizontal)
            .padding(.vertical, Layout.Style.bubbleInsetVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Palette.surface))
            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline))
            .accessibilityLabel(text)
    }

    // MARK: - Polish

    /// Who polishes this tone's text, and where to change it. The example above is the
    /// deterministic rules only; polish, when it's on, also shapes tone and word choice.
    private func polishRow(style: WritingStyle, provider: PolishProvider) -> some View {
        let configuration = model.lab.configuration(for: style)
        return HStack(alignment: .firstTextBaseline, spacing: Layout.Style.polishGap) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if provider == .off {
                    Text("AI polish is off")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    (Text("Polished with ")
                        .foregroundStyle(Palette.inkSecondary)
                        + Text(configuration?.name ?? provider.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.violet))
                        .font(Typography.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("With AI polish on, your style also shapes tone and word choice, not just capitals and punctuation.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.m)
            polishLink(hasConfiguration: configuration != nil, provider: provider)
        }
        .padding(.top, Layout.Style.polishTop)
    }

    @ViewBuilder
    private func polishLink(hasConfiguration: Bool, provider: PolishProvider) -> some View {
        if provider != .off && hasConfiguration {
            linkButton("Tune in Lab", help: "Opens the Lab") {
                model.section = .lab
            }
        } else {
            // Straight to Settings › Text & AI, where polish is turned on and chosen.
            linkButton(provider == .off ? "Turn on AI polish" : "Text & AI Settings", help: "Opens Settings › Text & AI") {
                guard preview.status == nil else { return }
                model.showSettings(.text)
            }
        }
    }

    private func linkButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Text(title)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(Typography.link)
        }
        .buttonStyle(StyleLinkButtonStyle())
        .help(help)
    }

    // MARK: - Saved

    private func savedNote(_ choice: SavedChoice) -> some View {
        HStack(spacing: Layout.Style.noteGap) {
            Image(systemName: "checkmark")
                .font(Typography.callout)
                .foregroundStyle(Palette.success)
                .accessibilityHidden(true)
            Text("Saved. \(choice.category.title) now uses \(choice.style.title).")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.leading, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// A text link in Signal blue, deep enough to read, dimming while pressed.
private struct StyleLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.accentInk)
            .opacity(configuration.isPressed ? Layout.Setup.pressedOpacity : 1)
            .contentShape(Rectangle())
            .flowFocusRing(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }
}

/// One app category in the list: its symbol, name and current tone. The selected row wears
/// Signal blue and a marker bar, so it never rests on colour alone.
private struct CategoryRow: View {
    let category: AppCategory
    let tone: WritingStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.Style.rowRadius, style: .continuous)
        Button(action: action) {
            HStack(alignment: .top, spacing: Layout.Style.rowGap) {
                Image(systemName: category.symbol)
                    .font(Typography.bodyLarge)
                    .foregroundStyle(isSelected ? Palette.accentInk : Palette.inkSecondary)
                    .frame(width: Layout.iconMedium)
                    .padding(.top, Layout.Style.rowSymbolTop)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Layout.Style.rowTitleGap) {
                    Text(category.title)
                        .font(Typography.headline)
                        .foregroundStyle(isSelected ? Palette.accentInk : Palette.ink)
                    Text(tone.title)
                        .font(Typography.callout)
                        .foregroundStyle(isSelected ? Palette.accentInk : Palette.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.Style.rowInsetHorizontal)
            .padding(.vertical, Layout.Style.rowInsetVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(isHovered && !isSelected ? Palette.surfaceHover : Palette.surface)
                    if isSelected { shape.fill(Palette.accentSoft) }
                }
            }
            .overlay(shape.strokeBorder(
                isSelected ? Palette.accentEdge : Palette.hairline,
                lineWidth: isSelected ? Layout.Main.selectionRing : Layout.Main.hairline
            ))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: Layout.Style.rowMarkerWidth)
                        .padding(.vertical, Layout.Style.rowMarkerInset)
                        .padding(.leading, Spacing.xs)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
            .flowFocusRing(shape, drawn: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: isSelected)
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel("\(category.title), \(tone.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One tone as a radio choice: name, what it does, and a radio mark. The chosen tone has a
/// filled mark and a Signal blue ring over a soft wash, so hue is never the only cue.
private struct ToneChoice: View {
    let style: WritingStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.Style.toneRadius, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: Layout.Style.toneTextGap) {
                Text(style.title)
                    .font(Typography.groupTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.trailing, Layout.Style.radioReserve)
                Text(style.summary)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Layout.Style.toneInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(Palette.surface)
                    if isSelected { shape.fill(Palette.accentSoft) }
                }
            }
            .overlay(shape.strokeBorder(
                isSelected ? Palette.accent : (isHovered ? Palette.control : Palette.hairline),
                lineWidth: isSelected ? Layout.Main.selectionRing : Layout.Main.hairline
            ))
            .overlay(alignment: .topTrailing) {
                radio
                    .padding(.trailing, Layout.Style.radioTrailing)
                    .padding(.top, Layout.Style.radioTop)
            }
            .contentShape(shape)
            .flowFocusRing(shape, drawn: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: isSelected)
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel(style.title)
        .accessibilityValue(style.summary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var radio: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Palette.accent : Color.clear)
            Circle()
                .strokeBorder(isSelected ? Palette.accent : Palette.control, lineWidth: Layout.Main.hairline)
            if isSelected {
                Circle()
                    .fill(Palette.onAccent)
                    .frame(width: Layout.Style.radioDot, height: Layout.Style.radioDot)
            }
        }
        .frame(width: Layout.Style.radio, height: Layout.Style.radio)
        .accessibilityHidden(true)
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

    /// The same sentence as it was said: no capitals, no punctuation.
    static func said(for category: AppCategory) -> String {
        spoken(for: category).lowercased().filter { !",.!?".contains($0) }
    }

    /// A typical app for the category, named beside the example ("In Messages").
    static func app(for category: AppCategory) -> String {
        switch category {
        case .personal: "Messages"
        case .work: "Slack"
        case .email: "Mail"
        case .other: "Notes"
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
