import SwiftUI

// MARK: - Home tokens (owned by the Home area; additive only)
//
// Home is an open canvas: the voice-field artwork sits behind the toolbar and the content, the
// greeting sits on it, and Recent dictation owns the main column with "Your setup" and a quiet
// "This week" beside it. Sizes step down with the detail column's width, as the handoff's
// breakpoints do (`Layout.Home.Scale`).

extension Palette {
    /// The voice-field artwork's colours (`VoiceField`): violet, blue and teal, a small apricot
    /// warmth and porcelain bars. It is the one place colour spreads over a surface; dark mode
    /// deepens every stop rather than inverting.
    enum Field {
        /// The pale disc behind the artwork and the halo ring around it.
        static let washA = Color.adaptive(light: 0xE1D9F5, dark: 0x242044)
        static let washB = Color.adaptive(light: 0xE2E7FC, dark: 0x142743)
        static let washC = Color.adaptive(light: 0xD8EFED, dark: 0x123B3B)
        static let halo = Color.adaptive(light: 0xFFFFFF, dark: 0x292A50)
        /// The coloured surface: violet, through blue, to teal.
        static let surfaceA = Color.adaptive(light: 0xC5B5EE, dark: 0x634987)
        static let surfaceB = Color.adaptive(light: 0x7596E9, dark: 0x3358A3)
        static let surfaceC = Color.adaptive(light: 0x79CBD3, dark: 0x267B8B)
        /// The two pigments that drift over it, and the apricot highlight.
        static let violet = Color.adaptive(light: 0xA780E7, dark: 0x8C56B9)
        static let teal = Color.adaptive(light: 0x41BFB2, dark: 0x159F92)
        static let warmth = Color.adaptive(light: 0xFFD8AC, dark: 0xC58A73)
        /// The five capsule bars: white, a touch cooler toward the corner.
        static let barA = Color.adaptive(light: 0xFFFFFF, dark: 0xF7F5FF)
        static let barB = Color.adaptive(light: 0xFFFFFF, dark: 0xF2F4FF)
        static let barC = Color.adaptive(light: 0xEFF6FF, dark: 0xE5F5FA)
    }
}

extension Layout {
    enum Home {
        /// The detail column's width when the window opens at its ideal size: what Home
        /// assumes until it has measured itself.
        static let designWidth: CGFloat = Layout.windowIdealWidth - Layout.Sidebar.width
        /// Dictations listed under Recent dictation.
        static let recentCount = 3

        // The greeting block.
        static let introTop: CGFloat = 31
        static let introBottom: CGFloat = 23
        /// Between the greeting and the hint line under it.
        static let introSpacing: CGFloat = 17
        /// Around the shortcut's keycap in the hint line.
        static let hintSpacing: CGFloat = 8
        /// Banners sit between the greeting and the columns.
        static let bannersBottom: CGFloat = 20

        // The columns.
        static let sectionHeaderBottom: CGFloat = 17
        /// Between the main column and the setup and week panels when the window is narrow.
        static let stackedGap: CGFloat = 28
        /// Between the setup and week panels side by side, and one over the other.
        static let sideBySideGap: CGFloat = 24
        static let asideGap: CGFloat = 20

        // "Your setup".
        static let setupHeadingSpacing: CGFloat = 9
        static let setupHeadingInsetTop: CGFloat = 18
        static let setupHeadingInsetBottom: CGFloat = 15
        static let setupHeadingInsetSide: CGFloat = 20
        static let setupRowInsetSide: CGFloat = 18
        static let setupRowInsetVertical: CGFloat = 14
        static let setupRowSpacing: CGFloat = 12
        static let setupSymbol: CGFloat = 31

        // "This week".
        static let weekInsetSide: CGFloat = 20
        static let weekInsetVertical: CGFloat = 19
        static let weekTitleBottom: CGFloat = 16
        static let weekLabelTop: CGFloat = 9
        static let weekNoteTop: CGFloat = 8
        static let weekDetailTop: CGFloat = 17
        static let weekDetailInset: CGFloat = 15
        static let weekDetailSpacing: CGFloat = 8
        static let weekFootTop: CGFloat = 14
        /// How much of the Dictionary's teal washes into the panel's far corner.
        static let weekTealMix: Double = 0.45

        /// Where the artwork goes: its width and height, how far its right edge sits inside the
        /// detail column (negative: past it), its top edge, and whether it shows the bars.
        struct FieldPlacement {
            let width: CGFloat
            let height: CGFloat
            let trailingInset: CGFloat
            let top: CGFloat
            let opacity: Double
            let showsBars: Bool
        }

        /// How much room Home has. The handoff's CSS breakpoints are window widths (1280, 1080,
        /// 720); the detail column is the sidebar's width narrower, so they're measured here
        /// from the column and shifted by it. The narrowest step is for completeness: the
        /// window's minimum width never gets there.
        enum Scale {
            case wide, regular, medium, narrow

            private static let wideAbove: CGFloat = 1280
            private static let regularAbove: CGFloat = 1080
            private static let mediumAbove: CGFloat = 720

            init(width: CGFloat) {
                let window = width + Layout.Sidebar.width
                if window > Self.wideAbove {
                    self = .wide
                } else if window > Self.regularAbove {
                    self = .regular
                } else if window > Self.mediumAbove {
                    self = .medium
                } else {
                    self = .narrow
                }
            }

            /// The greeting block's least height, and the space under it.
            var introMinHeight: CGFloat {
                switch self {
                case .wide: 242
                case .regular: 230
                case .medium: 222
                case .narrow: 210
                }
            }

            var introMargin: CGFloat {
                switch self {
                case .wide: 16
                case .regular, .medium, .narrow: 17
                }
            }

            /// How much of the content's width the greeting and hint may take, so they stay
            /// clear of the artwork.
            var copyFraction: CGFloat {
                switch self {
                case .wide, .regular: 0.65
                case .medium: 0.75
                case .narrow: 1
                }
            }

            /// Recent dictation over the setup and week panels, instead of beside them.
            var stacksColumns: Bool {
                switch self {
                case .wide, .regular: false
                case .medium, .narrow: true
                }
            }

            var asideWidth: CGFloat {
                switch self {
                case .wide: 272
                case .regular, .medium, .narrow: 240
                }
            }

            var columnGap: CGFloat {
                switch self {
                case .wide: 28
                case .regular, .medium, .narrow: 22
                }
            }

            var field: FieldPlacement {
                switch self {
                case .wide:
                    FieldPlacement(width: 650, height: 410, trailingInset: 3, top: -12, opacity: 1, showsBars: true)
                case .regular:
                    FieldPlacement(width: 570, height: 360, trailingInset: -40, top: -12, opacity: 1, showsBars: true)
                case .medium:
                    FieldPlacement(width: 480, height: 303, trailingInset: -64, top: -12, opacity: 1, showsBars: true)
                case .narrow:
                    // Only the field's glow, faded: the bars would crowd the words.
                    FieldPlacement(width: 370, height: 234, trailingInset: -180, top: -9, opacity: 0.35, showsBars: false)
                }
            }
        }
    }
}

extension Typography {
    /// Home's greeting: a step above page titles on the wide canvas, 32 pt at the narrowest.
    static func greeting(_ scale: Layout.Home.Scale) -> Font {
        switch scale {
        case .wide: Font.system(size: 44, weight: .semibold)
        case .regular: Font.system(size: 40, weight: .semibold)
        case .medium: Font.system(size: 37, weight: .semibold)
        case .narrow: Font.system(size: 32, weight: .semibold)
        }
    }

    /// "Hold fn anywhere to dictate. Release to insert."
    static func greetingHint(_ scale: Layout.Home.Scale) -> Font {
        switch scale {
        case .wide, .regular, .medium: Font.system(size: 18)
        case .narrow: Font.system(size: 17)
        }
    }

    /// The big number in "This week".
    static let weekNumeral = Font.system(size: 33, weight: .semibold).monospacedDigit()
}

extension Tracking {
    static func greeting(_ scale: Layout.Home.Scale) -> CGFloat {
        switch scale {
        case .wide: -1.7
        case .regular, .medium: -1.5
        case .narrow: -1
        }
    }

    static let weekNumeral: CGFloat = -1.2
}

extension Motion {
    /// The voice field's slow drift: one full cycle (the handoff's selected 2.0x speed).
    static let fieldCycle: Double = 20
    /// It redraws at most this often; a 20 s drift doesn't need more.
    static let fieldFrameInterval: Double = 1.0 / 30.0
}
