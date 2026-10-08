import SwiftUI

/// A toggleable filter capsule. Selected chips wear Signal blue, the app's colour for "chosen".
struct FilterChip: View {
    let title: String
    var symbol: String?
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

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
        .buttonStyle(FilterChipStyle(isSelected: isSelected, isFocused: isFocused))
        // The system ring would land on the chip's rectangular bounds and double the selected
        // border; the style draws its own, a gap outside the pill.
        .focusEffectDisabled()
        .focused($isFocused)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FilterChipStyle: ButtonStyle {
    let isSelected: Bool
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        FilterChipBody(configuration: configuration, isSelected: isSelected, isFocused: isFocused)
    }
}

private struct FilterChipBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let isFocused: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(Typography.caption)
            .lineLimit(1)
            .foregroundStyle(isSelected ? Palette.accent : (isHovered ? Palette.ink : Palette.inkSecondary))
            .padding(.horizontal, Spacing.m)
            .frame(height: Layout.Main.chipHeight)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(isSelected ? Palette.accent : Palette.hairline,
                                                              lineWidth: Layout.Main.hairline))
            .contentShape(Capsule())
            .flowFocusRing(Capsule(), drawn: isFocused)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Interaction.pressedScale : 1)
            .onHover { isHovered = $0 }
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: isSelected)
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var fill: Color {
        if isSelected { return Palette.accentSoft }
        if configuration.isPressed { return Palette.surfacePressed }
        return isHovered ? Palette.surfaceHover : Palette.surface
    }
}
