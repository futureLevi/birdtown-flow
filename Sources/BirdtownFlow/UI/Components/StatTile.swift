import SwiftUI

/// One headline number: a small eyebrow, a serif numeral that rolls up when it appears, and
/// an optional caption that gives the number meaning.
struct StatTile: View {
    let label: String
    let value: Int
    var unit: String?
    var caption: String?
    var symbol: String?

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(label)
            }
            .eyebrowStyle()

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(shown, format: .number)
                    .font(Typography.numeral)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(shown)))
                if let unit {
                    Text(unit)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            Spacer(minLength: 0)

            if let caption {
                Text(caption)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, minHeight: Layout.Main.statTileMinHeight, alignment: .topLeading)
        .cardSurface()
        .onAppear { roll(to: value) }
        .onChange(of: value) { _, newValue in roll(to: newValue) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([String(value), unit, caption].compactMap { $0 }.joined(separator: " "))
    }

    private func roll(to target: Int) {
        guard !reduceMotion else {
            shown = target
            return
        }
        withAnimation(Motion.countUp) { shown = target }
    }
}
