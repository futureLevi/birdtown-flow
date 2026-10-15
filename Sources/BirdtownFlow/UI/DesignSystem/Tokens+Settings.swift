import SwiftUI

// MARK: - Settings tokens (owned by the Settings area; additive only)
//
// Settings is a modal card over the main window: a quiet rail of the five sections on the left
// (the chosen one a Signal blue tint with accent text, a heavier weight and an edge, never hue
// alone), then a title header with the close button over a hairline, then grouped rows with
// the title and description on the left and the control on the right.

extension Layout {
    enum SettingsModal {
        /// The section rail. A narrower window shrinks the card; its pane scrolls.
        static let sidebarWidth: CGFloat = 215
        static let size = CGSize(width: 980, height: 790)
        /// Kept clear around the card, inside the window.
        static let margin: CGFloat = Spacing.xxxl
    }

    /// The Settings card's section rail and pane.
    enum SettingsRail {
        // The rail.
        static let sidePadding: CGFloat = 13
        static let topPadding: CGFloat = 25
        static let bottomPadding: CGFloat = 22
        /// Below the "Settings" title, before the first section.
        static let titleBottom: CGFloat = 15
        static let rowHeight: CGFloat = 46
        static let rowGap: CGFloat = 6
        static let rowRadius: CGFloat = Radius.field
        static let rowPadding: CGFloat = 11
        static let iconColumn: CGFloat = 22
        /// Above the version at the foot of the rail.
        static let footerTop: CGFloat = 20

        // The pane.
        static let headerHeight: CGFloat = 78
        static let panePadding: CGFloat = 28
        /// Above the first group; its own top padding makes up the handoff's 24 pt.
        static let paneTop: CGFloat = 4
        /// Above a first block that isn't a group (a notice, the About mark).
        static let firstBlockTop: CGFloat = 24
        /// Space above a group's title, and between its rows.
        static let groupTop: CGFloat = 28
        static let groupTitleGap: CGFloat = 7
        static let rowVertical: CGFloat = 17
        /// Between a row's words and its control.
        static let controlGap: CGFloat = 24
        /// Rows sit flush with the group's title: no card around them to inset from.
        static let rowInset: CGFloat = 0
        /// Opens 15 pt descriptions toward the handoff's 1.55 line height.
        static let detailLineSpacing: CGFloat = 3
    }
}

extension Typography {
    /// "Settings" at the top of the rail. 19 pt.
    static let settingsRailTitle = Font.system(size: 19, weight: .semibold)
}
