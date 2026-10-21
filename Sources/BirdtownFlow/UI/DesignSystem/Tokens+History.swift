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
        /// A row's padding inside its day card. The header and footer hold 36 pt controls, so
        /// 20 pt leaves the handoff's roughly 38 pt from the card edge to a line's centre.
        static let rowHorizontal: CGFloat = Spacing.xxl
        static let rowVertical: CGFloat = Spacing.xl
        /// The app's icon beside its name at the top of a row.
        static let appIcon: CGFloat = 26
        /// How wide a transcript runs before it wraps: about 69 characters of 19 pt text, so a
        /// wide window doesn't stretch lines past comfortable reading.
        static let transcriptMeasure: CGFloat = 820
        /// The bar down a selected row's leading edge: a second cue beside the blue wash, so
        /// selection never rests on colour alone.
        static let selectionMarker: CGFloat = 3
        /// Between the filter bar's groups, across and (when it wraps) down.
        static let filterGap: CGFloat = Spacing.m

        /// Home's Recent dictation card: the same rows a step smaller, so the card reads as a
        /// glance at the last few dictations rather than the full History page.
        enum Glance {
            static let appIcon: CGFloat = 22
            static let rowVertical: CGFloat = Spacing.l
            /// 17 pt on the same 1.6 line height: about 27 pt a line, the system's own is
            /// about 21.
            static let transcriptLine: CGFloat = 6
        }
    }
}

extension Typography {
    /// Home's Recent dictation rows (`HistoryRow.Density.glance`): dictated words at 17 pt
    /// instead of 19, the app name at 15, and times and details at 14.
    enum Glance {
        static let transcript = Font.system(size: 17)
        static let headline = Font.system(size: 15, weight: .semibold)
        static let callout = Font.system(size: 14)
    }
}

extension Palette {
    /// A search hit in a History row. Brighter and more opaque than `searchMatch` in dark
    /// mode, where a faint amber wash turns muddy brown on the navy card.
    static let historySearchMatch = Color.adaptive(light: 0xB7791F, lightAlpha: 0.22, dark: 0xFFC94D, darkAlpha: 0.42)
}
