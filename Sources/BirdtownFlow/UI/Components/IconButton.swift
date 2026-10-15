import SwiftUI

/// An icon-only button: quiet until hovered (then a Signal blue tint), and always labelled for
/// VoiceOver and tooltips.
struct IconButton: View {
    let symbol: String
    /// Spoken by VoiceOver and shown as the tooltip.
    let label: String
    var tint: Color = Palette.inkSecondary
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.bodyEmphasis)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(IconButtonStyle(tint: tint, drawsFocusRing: isFocused))
        // The style draws the 3 pt focus ring in its own rounded shape.
        .focusEffectDisabled()
        .focused($isFocused)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The square hover well behind icon buttons. Also usable on `Menu` labels. The system focus
/// ring follows the well's shape; to draw the 3 pt ring instead, pass the button's own
/// focus as `drawsFocusRing` and add `.focusEffectDisabled()` to the button (`IconButton` does).
struct IconButtonStyle: ButtonStyle {
    var tint: Color = Palette.inkSecondary
    var drawsFocusRing = false

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, tint: tint, drawsFocusRing: drawsFocusRing)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let drawsFocusRing: Bool

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .foregroundStyle(isHovered && isEnabled ? Palette.accentInk : tint)
            .frame(width: Layout.Main.iconButton, height: Layout.Main.iconButton)
            .background(shape.fill(configuration.isPressed ? Palette.surfacePressed
                                   : (isHovered && isEnabled ? Palette.accentSoft : .clear)))
            .contentShape(shape)
            .flowFocusRing(shape, drawn: drawsFocusRing)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Interaction.pressedScale : 1)
            .opacity(isEnabled ? 1 : Interaction.disabledOpacity)
            .onHover { isHovered = $0 }
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
