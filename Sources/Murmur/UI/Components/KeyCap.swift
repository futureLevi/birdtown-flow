import SwiftUI

/// A keyboard key drawn like the physical thing: a pale face, a hairline edge, a darker lip
/// along the bottom and a sliver of highlight on top. `isPressed` sinks it onto its lip,
/// which onboarding and Home use to act out "hold".
struct KeyCap: View {
    enum Size { case regular, large }

    let label: String
    var size: Size = .regular
    var isPressed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size == .large ? Radius.m : Radius.s, style: .continuous)
        let lip = size == .large ? Layout.Main.keyCapLipLarge : Layout.Main.keyCapLip

        Text(label)
            .font(size == .large ? Typography.title : Typography.keycap)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, size == .large ? Spacing.l : Spacing.s)
            .frame(
                minWidth: size == .large ? Layout.Main.keyCapMinWidthLarge : Layout.Main.keyCapMinWidth,
                minHeight: size == .large ? Layout.Main.keyCapHeightLarge : Layout.Main.keyCapHeight
            )
            .background {
                ZStack(alignment: .top) {
                    shape.fill(Palette.keyLip)
                    shape.fill(Palette.keyFace)
                        .padding(.bottom, isPressed ? 0 : lip)
                    Capsule()
                        .fill(Palette.keyHighlight)
                        .frame(height: Layout.Main.hairline)
                        .padding(.horizontal, Radius.s)
                        .padding(.top, Layout.Main.hairline)
                }
            }
            .overlay(shape.strokeBorder(Palette.hairlineStrong, lineWidth: Layout.Main.hairline))
            .offset(y: isPressed ? lip : 0)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: isPressed)
            .accessibilityLabel("\(label) key")
    }
}
