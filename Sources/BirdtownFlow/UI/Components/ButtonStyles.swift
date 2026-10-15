import SwiftUI

// Birdtown Flow's three button weights.
//
// Primary is the navy capsule (porcelain in dark mode): the one thing on a screen you're meant
// to press, so use it at most once per view. Secondary is an outlined surface with 8 pt
// corners; ghost is text that only shows its shape on hover.
//
// Every style follows `controlSize` (.small 35 pt, .regular 42 pt, .large 48 pt), dims when
// disabled, and gives hover and press feedback that collapses to plain fades under Reduce
// Motion.
//
// Destructive: a secondary or ghost button declared `Button(..., role: .destructive)` draws in
// `Palette.danger` and warms to `Palette.dangerSoft` on hover and press. `.flowDestructive` is
// the secondary button in those colours whatever the role. The navy primary never turns red.
//
// Keyboard focus: the system ring follows the button's shape (`flowFocusRing`).
//
// `compact` is the old size (13 pt text, 32 pt tall, a capsule), for onboarding, which the
// redesign leaves alone.

struct FlowPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlowButtonBody(configuration: configuration, kind: .primary)
    }
}

struct FlowSecondaryButtonStyle: ButtonStyle {
    /// Onboarding's size and shape; see the file header.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        FlowButtonBody(configuration: configuration, kind: .secondary, compact: compact)
    }
}

struct FlowGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlowButtonBody(configuration: configuration, kind: .ghost)
    }
}

/// The secondary button in danger colours, for irreversible actions ("Clear History…").
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
    var compact = false

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Primary actions are capsules; the quieter weights have 8 pt corners.
        if kind == .primary || compact {
            styled(Capsule())
        } else {
            styled(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
    }

    private func styled<S: InsettableShape>(_ shape: S) -> some View {
        configuration.label
            .font(font)
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

    /// Danger colours for secondary and ghost; the primary capsule stays navy.
    private var isDestructive: Bool {
        kind != .primary && (forcesDestructive || configuration.role == .destructive)
    }

    private var font: Font {
        if compact { return Typography.Compact.bodyEmphasis }
        switch controlSize {
        case .mini, .small: return Typography.caption
        case .large, .extraLarge: return Typography.bodyLargeEmphasis
        default: return Typography.bodyEmphasis
        }
    }

    private var height: CGFloat {
        if compact { return Layout.Setup.buttonHeight }
        switch controlSize {
        case .mini, .small: return Layout.Main.buttonHeightSmall
        case .large, .extraLarge: return Layout.Main.buttonHeightLarge
        default: return Layout.Main.buttonHeight
        }
    }

    private var horizontalPadding: CGFloat {
        if compact { return Spacing.l }
        switch controlSize {
        case .mini, .small: return Layout.Main.buttonPaddingSmall
        case .large, .extraLarge: return Layout.Main.buttonPaddingLarge
        default: return kind == .primary ? Layout.Main.buttonPaddingPrimary : Layout.Main.buttonPadding
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

    /// Secondary buttons wear the control outline (a destructive one changes only its text).
    private var border: Color {
        switch kind {
        case .primary, .ghost: .clear
        case .secondary: Palette.hairlineStrong
        }
    }
}
