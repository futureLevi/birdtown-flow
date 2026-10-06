import SwiftUI

/// A toggleable filter capsule. Selected chips are inked in; the count stays legible either way.
struct FilterChip: View {
    let title: String
    var symbol: String?
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let symbol {
                    Image(systemName: symbol)
                        .imageScale(.small)
                }
                Text(title)
                if let count {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .opacity(Interaction.dimmedOpacity)
                }
            }
        }
        .buttonStyle(FilterChipStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FilterChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        FilterChipBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct FilterChipBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(Typography.caption)
            .foregroundStyle(isSelected ? Palette.onChipSelected : (isHovered ? Palette.ink : Palette.inkSecondary))
            .padding(.horizontal, Spacing.m)
            .frame(height: Layout.Main.chipHeight)
            .background(Capsule(style: .continuous).fill(fill))
            .overlay(Capsule(style: .continuous).strokeBorder(isSelected ? Color.clear : Palette.hairline,
                                                              lineWidth: Layout.Main.hairline))
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? Interaction.pressedScale : 1)
            .onHover { isHovered = $0 }
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: isSelected)
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var fill: Color {
        if isSelected { return Palette.chipSelected }
        if configuration.isPressed { return Palette.surfacePressed }
        return isHovered ? Palette.surfaceHover : Palette.surface
    }
}
