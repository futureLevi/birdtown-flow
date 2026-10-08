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
/// A control that draws its own Signal blue ring instead passes `drawn:` the button's own focus
/// (a `@FocusState` bound with `.focused(_:)` on the `Button`) and puts `.focusEffectDisabled()`
/// on that `Button`. The ring sits `Layout.Main.focusRingGap` outside the control's edge so it
/// never merges with a selection border. It deliberately doesn't read `\.isFocused`: inside a
/// focusable container (History's list) that can report the container's focus, which would
/// ring every control in it.
struct FlowFocusRing<S: InsettableShape>: ViewModifier {
    let shape: S
    let isDrawn: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(.focusEffect, shape)
            .overlay {
                if isDrawn {
                    shape
                        .strokeBorder(Palette.accent, lineWidth: Layout.Main.focusRing)
                        .padding(-Layout.Main.focusRingGap)
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
