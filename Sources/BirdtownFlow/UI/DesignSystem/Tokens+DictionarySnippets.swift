import SwiftUI

// MARK: - Dictionary and Snippets tokens (owned by the library area; additive only)
//
// The Dictionary is a table with aligned columns ("When you say", an arrow, "Flow writes",
// "Used", the switch and an edit button); Snippets are two-part cards (the spoken trigger on a
// teal wash, the typed text beside it). Teal is the vocabulary accent.

extension Layout {
    enum Library {
        // The dictionary table. Header and rows share these widths so the columns line up.
        // Rows use the list type (`Typography.List`) and are a step tighter to match.
        static let tableInset: CGFloat = 22
        static let headVertical: CGFloat = 12
        static let rowVertical: CGFloat = 14
        static let rowMinHeight: CGFloat = 62
        static let columnGap: CGFloat = 14
        static let textColumnMin: CGFloat = 180
        static let arrowColumn: CGFloat = 24
        static let usedColumn: CGFloat = 94
        static let switchColumn: CGFloat = 42
        static let editColumn: CGFloat = Layout.Main.iconButton
        /// Between the search row and the table, and between the page's blocks.
        static let blockGap: CGFloat = 26
        /// Between a group's heading and its table, and between two groups.
        static let groupGap: CGFloat = 12

        // The snippet card.
        static let snippetTriggerWidth: CGFloat = 290
        static let snippetInset: CGFloat = 25
        static let snippetGap: CGFloat = 13
        static let snippetCardGap: CGFloat = 18
        static let snippetFooterTop: CGFloat = 21
        static let snippetFooterInset: CGFloat = 15
        /// Lines of an expansion shown on the card; the tooltip and the editor have all of it.
        static let expansionLines = 6

        // The tip under the snippets, and dashed panels in general.
        static let tipInsetVertical: CGFloat = 25
        static let tipInsetHorizontal: CGFloat = 28
        static let tipGap: CGFloat = 22
        static let tipIcon: CGFloat = 29
        static let dash: [CGFloat] = [6, 4]
    }
}

extension Typography {
    /// A snippet's spoken trigger on its card. 20 pt.
    static let snippetTrigger = Font.system(size: 20, weight: .semibold)
}

extension Tracking {
    static let snippetTrigger: CGFloat = -0.3
}

extension View {
    /// A dashed control-coloured outline with 14 pt corners: the handoff's quiet panels (empty
    /// states, tips) that don't need a card's weight.
    func dashedPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
        return self
            .overlay(shape.strokeBorder(
                Palette.control,
                style: StrokeStyle(lineWidth: Layout.Main.hairline, dash: Layout.Library.dash)
            ))
            .contentShape(shape)
    }
}
