import SwiftUI

// MARK: - HUD polish tokens (owned by the HUD area; additive only)

extension Palette.HUD {
    /// The cancelled pill steps back a little before it fades away.
    static let cancelledOpacity: Double = 0.85
}

extension Layout.HUD {
    /// The tallest a failure message's pill may grow when the message wraps to two lines.
    /// Fits `panelSize.height` minus `shadowMargin`, with room for the shadow above.
    static let messageMaxHeight: CGFloat = 52
    /// Lines a failure message may use before it truncates.
    static let failureLineLimit = 2
    /// The pill shrinks toward this scale as it hides, and to `cancelledScale` when cancelled.
    static let hiddenScale: CGFloat = 0.6
    static let cancelledScale: CGFloat = 0.92
    /// State content grows in from this scale as it cross-fades.
    static let contentEnterScale: CGFloat = 0.9
    /// The hands-free Cancel button grows in from this scale.
    static let accessoryEnterScale: CGFloat = 0.6
    /// Stacked translucent capsules that make up the pill's soft shadow.
    static let shadowLayers = 14
    /// How far the tight contact shadow spreads and drops below the pill.
    static let contactShadowSpread: CGFloat = 1
    /// The pill's edge and the keycap's border.
    static let strokeWidth: CGFloat = 1
    /// The soft disc behind the hands-free Stop button while the pointer is over it.
    static let stopHoverRing: CGFloat = 30
}

extension Motion {
    /// How long the HUD panel waits for the pill to finish fading out before it is ordered
    /// out. Covers `Motion.pill` (response 0.38) settling.
    static let pillSettle: Duration = .milliseconds(450)
}
