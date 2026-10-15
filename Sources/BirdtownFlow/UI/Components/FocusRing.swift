import SwiftUI

/// Keyboard focus for custom controls, in the control's own shape.
///
/// Apply inside a `ButtonStyle` body (or any focusable control's content) with the shape the
/// control is drawn in:
///
/// ```swift
/// configuration.label
///     ...
///     .background(Capsule().fill(fill))
///     .flowFocusRing(Capsule())
/// ```
///
/// It always shapes the system focus ring to `shape`, so the default ring follows the pill
/// instead of the control's rectangular bounds.
///
/// A control that draws its own ring instead passes `drawn:` the button's own focus (a
/// `@FocusState` bound with `.focused(_:)` on the `Button`) and puts `.focusEffectDisabled()`
/// on that `Button`. The ring is `Layout.Focus.width` (3 pt) thick and sits
/// `Layout.Focus.offset` (4 pt) outside the control's edge, so it never merges with a selection
/// border. It deliberately doesn't read `\.isFocused`: inside a focusable container (History's
/// list) that can report the container's focus, which would ring every control in it.
struct FlowFocusRing<S: InsettableShape>: ViewModifier {
    let shape: S
    let isDrawn: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(.focusEffect, shape)
            .overlay {
                if isDrawn {
                    // `strokeBorder` draws inside its shape, so grow the shape by the offset
                    // plus the stroke to leave the full offset clear inside the ring.
                    shape
                        .strokeBorder(Palette.focus, lineWidth: Layout.Focus.width)
                        .padding(-(Layout.Focus.offset + Layout.Focus.width))
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Shapes keyboard focus to `shape`, and draws the Signal blue ring when `drawn` is true;
    /// see `FlowFocusRing`.
    func flowFocusRing<S: InsettableShape>(_ shape: S, drawn: Bool = false) -> some View {
        modifier(FlowFocusRing(shape: shape, isDrawn: drawn))
    }
}
