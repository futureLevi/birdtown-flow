import SwiftUI

// Murmur's three button weights. Primary is Ember — the one thing on a screen you're meant
// to press — so use it at most once per view. Secondary is a quiet bordered surface;
// ghost is text that only shows its shape on hover.
//
// Every style follows `controlSize` (.small, .regular, .large), dims when disabled, and
// gives hover and press feedback that collapses to plain fades under Reduce Motion.

struct MurmurPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MurmurButtonBody(configuration: configuration, kind: .primary)
    }
}

struct MurmurSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MurmurButtonBody(configuration: configuration, kind: .secondary)
    }
}

struct MurmurGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MurmurButtonBody(configuration: configuration, kind: .ghost)
    }
}

extension ButtonStyle where Self == MurmurPrimaryButtonStyle {
    static var murmurPrimary: MurmurPrimaryButtonStyle { MurmurPrimaryButtonStyle() }
}

extension ButtonStyle where Self == MurmurSecondaryButtonStyle {
    static var murmurSecondary: MurmurSecondaryButtonStyle { MurmurSecondaryButtonStyle() }
}

extension ButtonStyle where Self == MurmurGhostButtonStyle {
    static var murmurGhost: MurmurGhostButtonStyle { MurmurGhostButtonStyle() }
}

private struct MurmurButtonBody: View {
    enum Kind { case primary, secondary, ghost }

    let configuration: ButtonStyleConfiguration
    let kind: Kind

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        configuration.label
            .font(controlSize == .small ? Typography.caption : Typography.bodyEmphasis)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: Layout.Main.hairline))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Interaction.pressedScale : 1)
            .opacity(isEnabled ? 1 : Interaction.disabledOpacity)
            .onHover { isHovered = $0 }
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
    }

    private var isActive: Bool { isHovered && isEnabled }

    private var height: CGFloat {
        switch controlSize {
        case .mini, .small: Layout.Main.buttonHeightSmall
        case .large, .extraLarge: Layout.Main.buttonHeightLarge
        default: Layout.Main.buttonHeight
        }
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini, .small: Spacing.s
        case .large, .extraLarge: Spacing.xl
        default: Spacing.m
        }
    }

    private var fill: Color {
        switch kind {
        case .primary:
            configuration.isPressed ? Palette.emberPressed : (isActive ? Palette.emberHover : Palette.ember)
        case .secondary:
            configuration.isPressed ? Palette.surfacePressed : (isActive ? Palette.surfaceHover : Palette.surface)
        case .ghost:
            configuration.isPressed ? Palette.surfacePressed : (isActive ? Palette.surfaceHover : .clear)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.onEmber
        case .secondary: Palette.ink
        case .ghost: isActive ? Palette.ink : Palette.inkSecondary
        }
    }

    private var border: Color {
        switch kind {
        case .primary, .ghost: .clear
        case .secondary: isActive ? Palette.hairlineStrong : Palette.hairline
        }
    }
}
