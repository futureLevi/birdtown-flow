import SwiftUI

/// One headline number on a soft grey tile: a small badge in the stat's colour beside its name,
/// a numeral that rolls up when it appears, and an optional caption that gives it meaning. The
/// same colour glows faintly in the tile's top-right corner.
struct StatTile: View {
    let label: String
    let value: Int
    var unit: String?
    var caption: String?
    var symbol: String?
    var tone: Palette.StatTone = .blue

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.Stat.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Layout.Stat.labelSpacing) {
                if let symbol {
                    StatBadge(symbol: symbol, tone: tone)
                }
                Text(label)
                    .font(Typography.statLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: Layout.Stat.unitSpacing) {
                Text(shown, format: .number)
                    .font(Typography.numeral)
                    .foregroundStyle(Palette.heading)
                    .contentTransition(.numericText(value: Double(shown)))
                if let unit {
                    Text(unit)
                        .font(Typography.statUnit)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .lineLimit(1)
            .padding(.top, Layout.Stat.numberTop)

            if let caption {
                Text(caption)
                    .font(Typography.statCaption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .padding(.top, Layout.Stat.captionTop)
            }
        }
        .padding(Layout.Stat.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            shape.fill(Palette.soft)
                .overlay(alignment: .topTrailing) { StatGlow(color: tone.glow) }
                .clipShape(shape)
        }
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

/// The stat's icon on a small tile lit from the top, built like the app icon.
private struct StatBadge: View {
    let symbol: String
    let tone: Palette.StatTone

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.Stat.badgeRadius, style: .continuous)
        Image(systemName: symbol)
            .font(Typography.statGlyph)
            .foregroundStyle(Palette.Stat.glyph)
            .frame(width: Layout.Stat.badge, height: Layout.Stat.badge)
            .background(shape.fill(LinearGradient(
                colors: [tone.badgeTop, tone.badgeBottom],
                startPoint: .top,
                endPoint: .bottom
            )))
            // A hairline of light along the top edge, like the icon tile's.
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [Palette.Stat.badgeHighlight, .clear], startPoint: .top, endPoint: .center),
                lineWidth: Layout.Stat.badgeHighlight
            ))
            .shadow(color: Palette.Stat.badgeShadow, radius: Layout.Stat.badgeShadowRadius, y: Layout.Stat.badgeShadowY)
            .accessibilityHidden(true)
    }
}

/// A soft elliptical light centred on the tile's top-right corner. Painted as a gradient, not
/// blurred, so snapshots show what people see.
private struct StatGlow: View {
    let color: Color

    var body: some View {
        let width = Layout.Stat.glowWidth
        RadialGradient(
            colors: [color, color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: width * Layout.Stat.glowFade
        )
        .frame(width: 2 * width, height: 2 * width)
        .scaleEffect(x: 1, y: Layout.Stat.glowHeight / width)
        // Centre the light on the corner the overlay is pinned to.
        .offset(x: width, y: -width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
