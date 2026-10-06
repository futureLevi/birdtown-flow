import SwiftUI

// Birdtown Flow's three button weights, all pill-shaped like the logo's bars.
//
// Primary is the navy pill (porcelain in dark mode), the logo's tile and ring: the one thing
// on a screen you're meant to press, so use it at most once per view. Secondary is a quiet
// bordered surface; ghost is text that only shows its shape on hover.
//
// Every style follows `controlSize` (.small, .regular, .large), dims when disabled, and
// gives hover and press feedback that collapses to plain fades under Reduce Motion.

struct FlowPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlowButtonBody(configuration: configuration, kind: .primary)
    }
}

struct FlowSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlowButtonBody(configuration: configuration, kind: .secondary)
    }
}

struct FlowGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlowButtonBody(configuration: configuration, kind: .ghost)
    }
}

extension ButtonStyle where Self == FlowPrimaryButtonStyle {
    static var flowPrimary: FlowPrimaryButtonStyle { FlowPrimaryButtonStyle() }
}

extension ButtonStyle where Self == FlowSecondaryButtonStyle {
    static var flowSecondary: FlowSecondaryButtonStyle { FlowSecondaryButtonStyle() }
}

extension ButtonStyle where Self == FlowGhostButtonStyle {
    static var flowGhost: FlowGhostButtonStyle { FlowGhostButtonStyle() }
}

private struct FlowButtonBody: View {
    enum Kind { case primary, secondary, ghost }

    let configuration: ButtonStyleConfiguration
    let kind: Kind

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = Capsule()
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
        case .mini, .small: Spacing.m
        case .large, .extraLarge: Spacing.xl
        default: Spacing.l
        }
    }

    private var fill: Color {
        switch kind {
        case .primary:
            configuration.isPressed ? Palette.primaryFillPressed : (isActive ? Palette.primaryFillHover : Palette.primaryFill)
        case .secondary:
            configuration.isPressed ? Palette.surfacePressed : (isActive ? Palette.surfaceHover : Palette.surface)
        case .ghost:
            configuration.isPressed ? Palette.surfacePressed : (isActive ? Palette.surfaceHover : .clear)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.onPrimary
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
