import SwiftUI

/// A raised surface: white on the cool canvas (deep navy on midnight), a hairline edge and the
/// faintest panel shadow, with 14 pt corners.
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.l
    var isSelected = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(isSelected: isSelected)
    }
}

extension View {
    /// Card chrome for views that manage their own padding (grouped lists, tiles). Selected
    /// cards wear Signal blue: a 1.5 pt ring over a soft blue wash. Pair it with a check or radio
    /// mark in the content, so "chosen" never rests on colour alone.
    func cardSurface(isSelected: Bool = false, isHovered: Bool = false, radius: CGFloat = Radius.l) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                ZStack {
                    shape.fill(isHovered ? Palette.surfaceHover : Palette.surface)
                    if isSelected { shape.fill(Palette.accentSoft) }
                }
            }
            .overlay(shape.strokeBorder(
                isSelected ? Palette.accent : Palette.hairline,
                lineWidth: isSelected ? Layout.Main.selectionRing : Layout.Main.hairline
            ))
            .clipShape(shape)
            .elevation(Elevation.card)
    }
}

/// A hairline between rows inside a card, inset to line up with the row text.
struct RowDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: Layout.Main.hairline)
            .padding(.leading, leadingInset)
    }
}
