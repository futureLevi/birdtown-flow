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

extension Layout {
    /// History's filter bar, day cards and rows.
    enum History {
        /// A row's padding inside its day card (and Home's Recent dictation card). A step
        /// tighter than the handoff's 20 pt, with the rows' type (`Typography.List`).
        static let rowHorizontal: CGFloat = Spacing.xxl
        static let rowVertical: CGFloat = Spacing.l
        /// The app's icon beside its name at the top of a row.
        static let appIcon: CGFloat = 22
        /// How wide a transcript runs before it wraps: about 77 characters of 17 pt text, so a
        /// wide window doesn't stretch lines past comfortable reading.
        static let transcriptMeasure: CGFloat = 820
        /// Line spacing for a row's transcript: 17 pt on a 1.6 line height is about 27 pt a
        /// line, and the system's own is about 21.
        static let transcriptLine: CGFloat = 6
        /// The bar down a selected row's leading edge: a second cue beside the blue wash, so
        /// selection never rests on colour alone.
        static let selectionMarker: CGFloat = 3
        /// Between the filter bar's groups, across and (when it wraps) down.
        static let filterGap: CGFloat = Spacing.m
    }
}

extension Palette {
    /// A search hit in a History row. Brighter and more opaque than `searchMatch` in dark
    /// mode, where a faint amber wash turns muddy brown on the navy card.
    static let historySearchMatch = Color.adaptive(light: 0xB7791F, lightAlpha: 0.22, dark: 0xFFC94D, darkAlpha: 0.42)
}
