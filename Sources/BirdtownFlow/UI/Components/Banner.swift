import SwiftUI

/// A full-width notice for something that needs the user: a missing permission, a model
/// download. Always says what's wrong in plain words and carries the fix as its accessory.
struct Banner<Accessory: View>: View {
    enum Tone { case info, warning, danger }

    let symbol: String
    let title: String
    let message: String
    var tone: Tone = .warning
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(Typography.bodyEmphasis)
                .foregroundStyle(tint)
                .frame(width: Layout.Main.bannerIcon, height: Layout.Main.bannerIcon)
                .background(Circle().fill(soft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.m)
            accessory
        }
        .padding(Spacing.m)
        .padding(.trailing, Spacing.xs)
        .cardSurface(radius: Radius.m)
        .accessibilityElement(children: .contain)
    }

    private var tint: Color {
        switch tone {
        case .info: Palette.inkSecondary
        case .warning: Palette.warning
        case .danger: Palette.danger
        }
    }

    private var soft: Color {
        switch tone {
        case .info: Palette.sunken
        case .warning: Palette.warningSoft
        case .danger: Palette.dangerSoft
        }
    }
}

/// A thin determinate ring — audio playback, small downloads.
struct ProgressRing: View {
    let progress: Double
    var tint: Color = Palette.ink
    var size: CGFloat = Layout.Main.progressRing

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.hairlineStrong, lineWidth: Layout.Main.progressRingLine)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: Layout.Main.progressRingLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// A small static status light: ready, failed, not downloaded. Anything that means
/// "recording" is a `SpectrumOrb` instead, never a coloured dot.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: Layout.Main.statusDot, height: Layout.Main.statusDot)
            .accessibilityHidden(true)
    }
}
