import SwiftUI

// MARK: - Style tokens (owned by the Style area; additive only)
//
// Style is a two-column page: the four app categories as a list on the left, and on the right
// one panel with a single tone choice (radio marks) and one live example for what's selected.
// Signal blue marks the choice; violet marks the "You say" microphone and the polish name.

extension Layout {
    enum Style {
        // The page: category list beside the panel.
        static let listWidth: CGFloat = 245
        static let columnGap: CGFloat = 26

        // A category row.
        static let listGap: CGFloat = 8
        static let rowInsetHorizontal: CGFloat = 14
        static let rowInsetVertical: CGFloat = 16
        static let rowGap: CGFloat = 12
        static let rowRadius: CGFloat = 11
        /// Nudges the symbol onto the title's first line.
        static let rowSymbolTop: CGFloat = 3
        static let rowTitleGap: CGFloat = 3
        /// The marker bar that comes with the selected row's colour.
        static let rowMarkerWidth: CGFloat = 3
        static let rowMarkerInset: CGFloat = 14

        // The panel.
        static let panelInset: CGFloat = 27
        static let panelSubtitleTop: CGFloat = 5

        // Tone choices.
        static let toneMinWidth: CGFloat = 190
        static let toneGap: CGFloat = 10
        static let toneInset: CGFloat = 18
        static let toneRadius: CGFloat = 10
        static let toneTextGap: CGFloat = 5
        /// Between the tone grid and the panel's title above it and the divider below it.
        static let toneBlockGap: CGFloat = 23

        // The radio mark in a tone's corner.
        static let radio: CGFloat = 17
        static let radioDot: CGFloat = 6
        static let radioTrailing: CGFloat = 15
        static let radioTop: CGFloat = 20
        /// Kept clear at the end of a tone's title so it never runs under the mark.
        static let radioReserve: CGFloat = 20

        // The preview.
        static let previewTop: CGFloat = 21
        static let previewHeadBottom: CGFloat = 17
        static let previewInset: CGFloat = 22
        static let previewRadius: CGFloat = 12
        static let speakerGap: CGFloat = 7
        static let saidTop: CGFloat = 9
        static let saidBottom: CGFloat = 21
        static let bubbleTop: CGFloat = 10
        static let bubbleInsetHorizontal: CGFloat = 23
        static let bubbleInsetVertical: CGFloat = 21

        // Under the preview: who polishes, and the saved note below the panel.
        static let polishTop: CGFloat = 22
        static let polishGap: CGFloat = 16
        static let noteGap: CGFloat = 8

        // The apps panel under the tone panel.
        static let appsHeadBottom: CGFloat = 10
        static let appIcon: CGFloat = 28
        static let appRowGap: CGFloat = 12
        static let appRowVertical: CGFloat = 10
        static let appsNoteTop: CGFloat = 14
    }
}
