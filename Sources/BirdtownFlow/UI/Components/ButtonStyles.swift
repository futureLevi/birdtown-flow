import SwiftUI

// Birdtown Flow's three button weights, all pill-shaped like the logo's bars.
//
// Primary is the navy pill (porcelain in dark mode), the logo's tile and ring: the one thing
// on a screen you're meant to press, so use it at most once per view. Secondary is a quiet
// bordered surface; ghost is text that only shows its shape on hover.
//
// Every style follows `controlSize` (.small, .regular, .large), dims when disabled, and
// gives hover and press feedback that collapses to plain fades under Reduce Motion.
//
// Destructive: a secondary or ghost button declared `Button(..., role: .destructive)` draws in
// `Palette.danger` and warms to `Palette.dangerSoft` on hover and press. `.flowDestructive` is
// the secondary pill in those colours whatever the role. The navy primary never turns red.
//
// Keyboard focus: the system ring follows the pill (`flowFocusRing`).

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

/// The secondary pill in danger colours, for irreversible actions ("Clear History…").
/// Prefer `.flowSecondary` with `role: .destructive`; use this where the role can't be set.
struct FlowDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlowButtonBody(configuration: configuration, kind: .secondary, forcesDestructive: true)
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

extension ButtonStyle where Self == FlowDestructiveButtonStyle {
    static var flowDestructive: FlowDestructiveButtonStyle { FlowDestructiveButtonStyle() }
}

private struct FlowButtonBody: View {
    enum Kind { case primary, secondary, ghost }

    let configuration: ButtonStyleConfiguration
    let kind: Kind
    var forcesDestructive = false

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
            .flowFocusRing(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Interaction.pressedScale : 1)
            .opacity(isEnabled ? 1 : Interaction.disabledOpacity)
            .onHover { isHovered = $0 }
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
    }

    private var isActive: Bool { isHovered && isEnabled }

    /// Danger colours for secondary and ghost; the primary pill stays navy.
    private var isDestructive: Bool {
        kind != .primary && (forcesDestructive || configuration.role == .destructive)
    }

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
        case .secondary where isDestructive:
            configuration.isPressed || isActive ? Palette.dangerSoft : Palette.surface
        case .secondary:
            configuration.isPressed ? Palette.surfacePressed : (isActive ? Palette.surfaceHover : Palette.surface)
        case .ghost where isDestructive:
            configuration.isPressed || isActive ? Palette.dangerSoft : .clear
        case .ghost:
            configuration.isPressed ? Palette.surfacePressed : (isActive ? Palette.surfaceHover : .clear)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.onPrimary
        case .secondary where isDestructive: Palette.danger
        case .ghost where isDestructive: Palette.danger
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
