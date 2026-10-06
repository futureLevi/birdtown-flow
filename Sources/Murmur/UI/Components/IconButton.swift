import SwiftUI

/// An icon-only button: quiet until hovered, and always labelled for VoiceOver and tooltips.
struct IconButton: View {
    let symbol: String
    /// Spoken by VoiceOver and shown as the tooltip.
    let label: String
    var tint: Color = Palette.inkSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.bodyEmphasis)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(IconButtonStyle(tint: tint))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The square hover well behind icon buttons. Also usable on `Menu` labels.
struct IconButtonStyle: ButtonStyle {
    var tint: Color = Palette.inkSecondary

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, tint: tint)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        configuration.label
            .foregroundStyle(isHovered && isEnabled ? Palette.ink : tint)
            .frame(width: Layout.Main.iconButton, height: Layout.Main.iconButton)
            .background(shape.fill(configuration.isPressed ? Palette.surfacePressed
                                   : (isHovered && isEnabled ? Palette.surfaceHover : .clear)))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Interaction.pressedScale : 1)
            .opacity(isEnabled ? 1 : Interaction.disabledOpacity)
            .onHover { isHovered = $0 }
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
