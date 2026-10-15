import SwiftUI

// MARK: - Lab tokens (owned by the Lab area; additive only)
//
// The Lab is three regions: the configuration list, the editor panel and the test panel, with
// results under them. Violet is the accent: tuning, the prompt's variables.

extension Layout {
    /// The Lab: polish configurations, their editor, the test text and results.
    enum Lab {
        /// The configuration list, and the gap between it and the panels beside it.
        static let listWidth: CGFloat = 224
        static let columnGap: CGFloat = 25
        /// The open row's marker bar, inside its left edge: width and the space above and below.
        static let markerWidth: CGFloat = 3
        static let markerInset: CGFloat = 14
        /// A panel's header: the title, save status and icon buttons over a hairline.
        static let panelHeaderVertical: CGFloat = 14
        /// Space between form rows and between a row's two columns.
        static let formGap: CGFloat = 18
        static let fieldHeight: CGFloat = 43
        /// The prompt editor: tall enough for a paragraph, 17 pt on a 1.7 line height.
        static let instructionsHeight: CGFloat = 235
        static let instructionsLineSpacing: CGFloat = 8
        /// The test text and its result sit in wells this tall.
        static let sampleHeight: CGFloat = 165
        static let appFieldWidth: CGFloat = 150
        static let styleWidth: CGFloat = 130
        static let categoryWidth: CGFloat = 180
        /// The effort control stops growing here; its segments share the width.
        static let effortMaxWidth: CGFloat = 440
        static let segmentVertical: CGFloat = 6
        static let segmentRadius: CGFloat = 6
        static let segmentTrack: CGFloat = 4
        static let segmentTrackRadius: CGFloat = 9
        static let segmentGap: CGFloat = 3
        /// How far a long segment title may shrink before it truncates.
        static let segmentMinScale: CGFloat = 0.8
        /// The refused reply, shown on request, scrolls past this.
        static let replyMaxHeight: CGFloat = 160
    }
}

extension Elevation {
    /// The chosen segment lifting off its track.
    static let segment = Shadow(
        color: Color.adaptive(light: 0x0E183C, lightAlpha: 0.08, dark: 0x000000, darkAlpha: 0.30),
        radius: 2,
        y: 1
    )
}

extension Typography {
    /// The effort control's segments: 15 pt, heavier for the chosen one.
    static let segment = Font.system(size: 15)
    static let segmentSelected = Font.system(size: 15, weight: .semibold)
}
