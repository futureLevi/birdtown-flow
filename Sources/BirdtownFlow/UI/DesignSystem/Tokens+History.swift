import SwiftUI

// MARK: - History and Home tokens (owned by the Main area; additive only)

extension Layout.Main {
    /// Extra room at the end of a page's scroll content while a floating bar (undo toast,
    /// selection bar) is up, so the last row can scroll clear of it: the bar's height (its
    /// tallest control plus vertical padding) and its bottom margin, less the page padding
    /// already there, plus a gap.
    static let floatingBarClearance: CGFloat =
        Layout.Main.iconButton + 2 * Spacing.s + Spacing.xl - Spacing.page + Spacing.l
}

extension Palette {
    /// A search hit in a History row. Brighter and more opaque than `searchMatch` in dark
    /// mode, where a faint amber wash turns muddy brown on the navy card.
    static let historySearchMatch = Color.adaptive(light: 0xB7791F, lightAlpha: 0.22, dark: 0xFFC94D, darkAlpha: 0.42)
}
