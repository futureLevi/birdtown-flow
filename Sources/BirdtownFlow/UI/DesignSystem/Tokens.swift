import AppKit
import SwiftUI

// MARK: - Birdtown Flow design language
//
// "Navy and spectrum", taken straight from the logo. Navy ink on porcelain (midnight navy in
// dark mode), white surfaces, rounded shapes. One solid accent, Signal blue, marks selection,
// focus and links. Primary actions are navy pills (porcelain in dark mode), like the logo's
// tile and ring. The spectrum, the logo's disc, means "your voice is live" and nothing else:
// the recording orb, the thinking ring, download progress and the onboarding hero. Never
// static chrome, text or backgrounds. SF Pro Rounded for titles and numbers echoes the
// logo's pill bars; SF Pro for everything you read, including your own words. Motion is
// springy but brief, and collapses to fades under Reduce Motion.
//
// Rules:
//  - Views never contain literal colours, sizes, radii or durations. Use these tokens; if a
//    token is missing, add it here.
//  - Spectrum only for live states (`Spectrum`, `SpectrumOrb`). Signal blue only for
//    selection, focus, links and toggles. At most one primary (navy) action per view.
//  - Every animation goes through `Motion` so Reduce Motion is honoured everywhere.

enum Palette {
    /// Window background. Porcelain / midnight navy.
    static let canvas = Color.adaptive(light: 0xF6F7FB, dark: 0x0B1026)
    /// Raised surfaces: cards, rows, popovers.
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x141A33)
    /// Hovered surface.
    static let surfaceHover = Color.adaptive(light: 0xEEF1F8, dark: 0x1B2242)
    /// Inset wells: text inputs, code, empty states.
    static let sunken = Color.adaptive(light: 0xECEFF6, dark: 0x080C1D)
    /// 1px separators and card borders, tinted navy.
    static let hairline = Color.adaptive(light: 0x0E183C, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.08)
    /// Stronger border for focused inputs and selected cards.
    static let hairlineStrong = Color.adaptive(light: 0x0E183C, lightAlpha: 0.18, dark: 0xFFFFFF, darkAlpha: 0.18)

    /// Primary text: the logo's navy.
    static let ink = Color.adaptive(light: 0x0E183C, dark: 0xEEF1FA)
    /// Secondary text: metadata, descriptions.
    static let inkSecondary = Color.adaptive(light: 0x4A5478, dark: 0xA5ACC6)
    /// Tertiary text: placeholders, disabled, timestamps.
    static let inkTertiary = Color.adaptive(light: 0x8A91AC, dark: 0x6A7191)

    /// The primary action: a navy pill in light mode, porcelain in dark (the logo's tile and ring).
    static let primaryFill = Color.adaptive(light: 0x0E183C, dark: 0xEEF1FA)
    static let primaryFillHover = Color.adaptive(light: 0x1D2B5E, dark: 0xFFFFFF)
    static let primaryFillPressed = Color.adaptive(light: 0x08102A, dark: 0xD9DDEC)
    /// Text and icons on `primaryFill`.
    static let onPrimary = Color.adaptive(light: 0xFFFFFF, dark: 0x0E183C)

    /// Signal blue, from the logo's spectrum: selection, focus rings, links, toggles.
    static let accent = Color.adaptive(light: 0x4256F0, dark: 0x8291FF)
    /// Signal blue at low strength: selected backgrounds, badges.
    static let accentSoft = Color.adaptive(light: 0x4F61FB, lightAlpha: 0.10, dark: 0x8291FF, darkAlpha: 0.18)
    /// Text drawn on a Signal blue fill.
    static let onAccent = Color.white

    /// Deprecated names from the Ember era. They point at Signal blue so nothing breaks while
    /// views migrate to `accent`, `primaryFill` or the spectrum.
    static let ember = accent
    static let emberSoft = accentSoft
    static let onEmber = onAccent

    static let success = Color.adaptive(light: 0x1E8F63, dark: 0x4FD39A)
    static let successSoft = Color.adaptive(light: 0x1E8F63, lightAlpha: 0.10, dark: 0x4FD39A, darkAlpha: 0.16)
    static let warning = Color.adaptive(light: 0xB7791F, dark: 0xF0B04A)
    static let warningSoft = Color.adaptive(light: 0xB7791F, lightAlpha: 0.10, dark: 0xF0B04A, darkAlpha: 0.15)
    static let danger = Color.adaptive(light: 0xD03A4E, dark: 0xFF6B7A)
    static let dangerSoft = Color.adaptive(light: 0xD03A4E, lightAlpha: 0.09, dark: 0xFF6B7A, darkAlpha: 0.15)

    /// The pill is always dark, whatever the appearance: it floats over arbitrary content.
    /// Its navy is the logo tile's.
    enum HUD {
        static let fill = Color(hex: 0x0B1230, alpha: 0.95)
        static let stroke = Color.white.opacity(0.12)
        static let ink = Color.white.opacity(0.94)
        static let inkSecondary = Color.white.opacity(0.58)
        /// The logo's warm-white bars.
        static let bar = Color(hex: 0xFEFCF8, alpha: 0.95)
        static let barIdle = Color.white.opacity(0.30)
        /// Deprecated: the spectrum orb replaces the Ember record light.
        static let ember = Color(hex: 0x8291FF)
        static let success = Color(hex: 0x4FD39A)
        static let danger = Color(hex: 0xFF6B7A)
    }
}

/// The logo's spectrum, for live states only. Colours are `LogoPainter`'s measured hue stops,
/// so the orb in the pill is the logo's disc, not an approximation of it.
enum Spectrum {
    /// The 36 hue stops in SwiftUI's clockwise order, starting at 3 o'clock.
    static let colors: [Color] = {
        let stops = LogoPainter.Colors.hueMid
        // LogoPainter's stops run counter-clockwise; SwiftUI's angular gradients run clockwise.
        let clockwise = [stops[0]] + stops.dropFirst().reversed()
        return (clockwise + [stops[0]]).map { Color(hex: $0) }
    }()

    /// The disc's hues around a centre, turned by `rotation`.
    static func angular(rotation: Angle = .zero) -> AngularGradient {
        AngularGradient(colors: colors, center: .center, angle: rotation)
    }

    /// A left-to-right sweep for progress bars: cool to warm, like a voice warming up.
    static var progress: LinearGradient {
        LinearGradient(
            colors: [0x3082F8, 0x6F54FB, 0xB348ED, 0xFB7896, 0xFEA964].map { Color(hex: $0) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// The muted violet-grey the disc fades toward at its centre.
    static let centre = Color(hex: LogoPainter.Colors.centreNeutral)
}

extension Layout {
    /// `SpectrumOrb` sizes. The orb is the logo's disc; it never appears smaller than `small`,
    /// below which the hues blur into grey.
    enum Orb {
        /// Menu bar window status, list rows.
        static let small: CGFloat = 8
        /// The record light in the pill, the Dictate button while recording.
        static let medium: CGFloat = 12
        /// Onboarding's "try it" moment.
        static let large: CGFloat = 44
        /// The thinking ring's hole, as a fraction of the orb's radius.
        static let ringHole: CGFloat = 0.56
    }
}

extension Motion {
    /// Seconds per turn of the live orb: slow enough to feel calm, fast enough to read as alive.
    static let orbTurn: Double = 9
    /// Seconds per turn of the thinking ring.
    static let orbThinkingTurn: Double = 1.25
}

enum Typography {
    /// Page titles: "History", "Good evening, Levi". Rounded, like the logo's bars.
    static let display = Font.system(size: 28, weight: .semibold, design: .rounded)
    /// Section titles inside a page, sheet titles.
    static let title = Font.system(size: 19, weight: .semibold, design: .rounded)
    /// Big numbers in stat tiles.
    static let numeral = Font.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()
    /// Card and row headings.
    static let headline = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    /// Dictated text: the user's own words, set a step larger than interface text.
    static let transcript = Font.system(size: 15)
    static let transcriptLarge = Font.system(size: 17)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11, weight: .medium)
    /// Small uppercase labels above sections. Use with `.textCase(.uppercase)` and `Tracking.eyebrow`.
    static let eyebrow = Font.system(size: 10.5, weight: .semibold)
    /// Keycaps and shortcuts.
    static let keycap = Font.system(size: 12, weight: .medium, design: .rounded)
    static let mono = Font.system(size: 12, design: .monospaced)
    /// HUD labels.
    static let hud = Font.system(size: 12, weight: .medium, design: .rounded)
    static let hudNumeral = Font.system(size: 12, weight: .medium, design: .rounded).monospacedDigit()
}

enum Tracking {
    static let eyebrow: CGFloat = 0.8
    static let display: CGFloat = -0.4
    static let title: CGFloat = -0.2
}

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
    /// Page padding inside the detail column.
    static let page: CGFloat = 32
    /// Line spacing for transcript text.
    static let transcriptLine: CGFloat = 4
}

enum Radius {
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let l: CGFloat = 14
    static let xl: CGFloat = 20
}

enum Layout {
    static let sidebarWidth: CGFloat = 220
    /// Reading measure for the detail column.
    static let contentMaxWidth: CGFloat = 760
    static let windowMinWidth: CGFloat = 860
    static let windowMinHeight: CGFloat = 560
    static let windowIdealWidth: CGFloat = 1040
    static let windowIdealHeight: CGFloat = 700
    static let rowMinHeight: CGFloat = 44
    static let iconSmall: CGFloat = 16
    static let iconMedium: CGFloat = 20
    static let iconLarge: CGFloat = 28
    static let appIcon: CGFloat = 18
    static let settingsWidth: CGFloat = 620
    static let onboardingSize = CGSize(width: 640, height: 520)

    enum HUD {
        /// Resting pill while idle.
        static let idleSize = CGSize(width: 40, height: 8)
        static let height: CGFloat = 36
        static let listeningWidth: CGFloat = 132
        static let handsFreeWidth: CGFloat = 196
        static let processingWidth: CGFloat = 92
        static let messageMaxWidth: CGFloat = 360
        /// Gap between the pill and the bottom of the visible screen area (above the Dock).
        static let bottomInset: CGFloat = 18
        static let barCount = 15
        static let barWidth: CGFloat = 2.5
        static let barSpacing: CGFloat = 2.5
        static let barMinHeight: CGFloat = 3
        static let barMaxHeight: CGFloat = 20
        static let recordDot: CGFloat = 7
    }
}

enum Elevation {
    /// Cards at rest.
    struct Shadow { let color: Color; let radius: CGFloat; let y: CGFloat }
    static let card = Shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    static let raised = Shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    static let hud = Shadow(color: .black.opacity(0.35), radius: 16, y: 6)
}

// MARK: - HUD additions (owned by the HUD area; additive only)

extension Palette.HUD {
    /// Waveform bars are drawn in the logo's warm white (`bar`); opacity carries loudness.
    static let barRestOpacity: Double = 0.42
    static let barPeakOpacity: Double = 0.95
    /// The resting idle pill is a whisper until hovered.
    static let idleOpacity: Double = 0.4
    /// Edge of the resting pill (before `idleOpacity`), so it stays visible on dark content.
    static let idleStroke = Color.white.opacity(0.5)
    /// Shadow size of the resting pill, relative to `Elevation.hud`.
    static let idleShadowScale: CGFloat = 0.3
    /// Round HUD buttons at rest and under the pointer.
    static let control = Color.white.opacity(0.08)
    static let controlHover = Color.white.opacity(0.18)
    /// The done check: the logo's warm white, a nod rather than a celebration.
    static let check = Color(hex: 0xFEFCF8)
    static let dangerSoft = Color(hex: 0xFF6B7A, alpha: 0.18)
    /// The pill's shadow is built from stacked layers (see `HUDPillBody`), shaped by
    /// `Elevation.hud`'s radius and offset.
    static let shadow = Color.black
    static let shadowLayerOpacity: Double = 0.018
    static let contactShadowOpacity: Double = 0.18
}

extension Layout.HUD {
    /// Fixed panel size: fits the widest state plus room for the pill's shadow, so state
    /// changes never move or resize the window.
    static let panelSize = CGSize(width: 480, height: 88)
    /// Space under the pill, inside the panel, for its shadow.
    static let shadowMargin: CGFloat = 26
    /// The idle pill grows to this height to show its hint.
    static let hintHeight: CGFloat = 26
    /// Extra pointer slack around the tiny idle pill.
    static let hitSlop: CGFloat = 10
    static let buttonSize: CGFloat = 24
    /// The spectrum orb as the record light, and as the hands-free Stop button.
    static let orb: CGFloat = 14
    static let stopOrb: CGFloat = 24
    static let stopHoverScale: CGFloat = 1.08
    /// How far the bars rise into their resting dome while the orb spins.
    static let thinkingLift: CGFloat = 2.5
    static let stopGlyph: CGFloat = 8
    static let stopGlyphRadius: CGFloat = 2
    static let timerWidth: CGFloat = 32
    static let checkSize: CGFloat = 14
    static let checkStroke: CGFloat = 2
    /// The smaller check inside the "copied" notice's glyph circle.
    static let noticeCheckSize: CGFloat = 10
    static let failureGlyph: CGFloat = 16
    static let contentPadding: CGFloat = 14
    static let hintSpacing: CGFloat = 5
    static let keycapPadding: CGFloat = 4
    static let keycapHeight: CGFloat = 15
    /// AppKit twins of `Typography.hud` / `.hudKeycap`, used to measure labels so the pill
    /// can spring to an exact width. Keep in step with those fonts.
    static let labelPointSize: CGFloat = 12
    static let keycapPointSize: CGFloat = 10.5
    /// How far silent bars ripple, so the user can see the mic is live.
    static let idleShimmer: CGFloat = 1.6
}

extension Typography {
    static let hudKeycap = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    static let hudGlyph = Font.system(size: 10, weight: .bold)
}

extension Motion {
    /// Failure shake offsets, played once (returns to the first).
    static let shakeOffsets: [CGFloat] = [0, -7, 6, -4, 2]
    static let shakeStep = Animation.easeInOut(duration: 0.055)
    /// The done check drawing itself.
    static let checkDraw = Animation.easeOut(duration: 0.34).delay(0.08)
    /// Per-bar spring for the live waveform (same feel as `bars`).
    static let barStiffness: Double = 420
    static let barDamping: Double = 26
    /// `pill`'s spring parameters, for code that evaluates the curve itself (the README film).
    static let pillResponse: Double = 0.38
    static let pillDamping: Double = 0.74
    /// The bars' slow breathing while the orb spins, cycles per second.
    static let thinkingFrequency: Double = 0.8
}

/// Every animation goes through here so Reduce Motion is honoured consistently.
enum Motion {
    /// Small state changes: hover, toggles, selection.
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.86)
    /// Layout changes: rows appearing, sections expanding.
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Large movements: page transitions, onboarding steps.
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
    /// The HUD pill changing shape — a touch of overshoot so it feels alive.
    static let pill = Animation.spring(response: 0.38, dampingFraction: 0.74)
    /// Waveform bars following the voice.
    static let bars = Animation.interpolatingSpring(stiffness: 420, damping: 26)
    static let fadeFast = Animation.easeOut(duration: 0.14)
    static let fade = Animation.easeOut(duration: 0.22)

    /// The animation to use, or a short cross-fade when the user prefers reduced motion.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : animation
    }
}

// MARK: - Setup surfaces: onboarding, Settings, menu bar

extension Typography {
    /// The product name on the welcome and About screens.
    static let hero = Font.system(size: 40, weight: .bold, design: .rounded)
    /// The paragraph under an onboarding title: a step larger than body, for calm reading.
    static let lead = Font.system(size: 14)
    /// Recent dictations in the menu bar window: the user's words, at menu scale.
    static let transcriptSmall = Font.system(size: 13)
    /// The symbol inside an onboarding step's glyph.
    static let stepGlyph = Font.system(size: 22, weight: .regular)
    /// Big keycaps in the shortcut picker.
    static let keycapLarge = Font.system(size: 19, weight: .medium, design: .rounded)
}

extension Layout {
    enum Setup {
        // Icon frames: the artwork keeps the standard macOS margin (its tile fills ~80 % of
        // the frame), so these are about a quarter larger than the tile they show.
        static let appIcon: CGFloat = 120
        static let aboutIcon: CGFloat = 80
        static let menuIcon: CGFloat = 36
        /// Every Settings tab is this tall and scrolls inside, so the window never outgrows a
        /// 13" screen and doesn't jump in size between tabs.
        static let settingsHeight: CGFloat = 620
        static let stepGlyph: CGFloat = 52
        /// Reading measure for onboarding copy.
        static let measure: CGFloat = 420
        /// Width of the controls under onboarding copy.
        static let controlsWidth: CGFloat = 452
        static let buttonMinWidth: CGFloat = 104
        static let buttonHeight: CGFloat = 32
        static let menuButtonHeight: CGFloat = 36
        static let keyCap: CGFloat = 22
        static let keyCapLarge: CGFloat = 48
        /// The darker edge under a keycap that makes it read as a physical key.
        static let keyLip: CGFloat = 1
        static let progressDot: CGFloat = 6
        static let progressDotActive: CGFloat = 20
        static let progressBarHeight: CGFloat = 4
        static let statusDot: CGFloat = 7
        static let menuBarWidth: CGFloat = 320
        static let selectionStroke: CGFloat = 1.5
        static let footerHeight: CGFloat = 72
        static let pressedOpacity: Double = 0.84
        static let disabledOpacity: Double = 0.4
        /// White wash over a hovered Ember button.
        static let hoverLift: Double = 0.08
        static let hairline: CGFloat = 1
    }
}

extension Elevation {
    /// No shadow, for marks drawn too small for one to read as anything but a smudge.
    static let flat = Shadow(color: .clear, radius: 0, y: 0)
}

extension Motion {
    /// A confirmation landing: the check that pops in when a permission is granted.
    static let confirm = Animation.spring(response: 0.36, dampingFraction: 0.62)
    /// Pause on a just-granted permission before onboarding moves on by itself.
    static let autoAdvanceDelay: Duration = .milliseconds(900)
    /// How long a "Copied" confirmation stays visible.
    static let confirmationHold: Duration = .milliseconds(1400)
    /// How far onboarding content travels as it slides between steps.
    static let stepTravel: CGFloat = 36
    /// Press feedback for custom buttons.
    static let pressedScale: CGFloat = 0.97
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// A colour that resolves per appearance, so tokens follow light/dark automatically.
    static func adaptive(
        light: UInt32, lightAlpha: Double = 1,
        dark: UInt32, darkAlpha: Double = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            let alpha = isDark ? darkAlpha : lightAlpha
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        })
    }
}

extension View {
    /// Applies a token shadow.
    func elevation(_ shadow: Elevation.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    /// Section label style: small, uppercase, tracked.
    func eyebrowStyle() -> some View {
        self.font(Typography.eyebrow)
            .tracking(Tracking.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkTertiary)
    }
}

// MARK: - Main window and shared components
//
// Namespaced so tokens added by other areas can't collide with these on merge.

extension Layout {
    enum Main {
        /// Line widths: resting card edge, selected ring.
        static let hairline: CGFloat = 1
        static let selectionRing: CGFloat = 1.5
        static let buttonHeight: CGFloat = 30
        static let buttonHeightSmall: CGFloat = 24
        static let buttonHeightLarge: CGFloat = 38
        static let iconButton: CGFloat = 28
        static let chipHeight: CGFloat = 28
        static let searchFieldHeight: CGFloat = 32
        static let searchFieldWidth: CGFloat = 260
        static let keyCapHeight: CGFloat = 22
        static let keyCapMinWidth: CGFloat = 26
        static let keyCapHeightLarge: CGFloat = 44
        static let keyCapMinWidthLarge: CGFloat = 56
        /// The darker lip along a keycap's bottom edge — it's what makes it read as a key.
        static let keyCapLip: CGFloat = 1.5
        static let keyCapLipLarge: CGFloat = 3
        static let statusDot: CGFloat = 7
        static let rowIcon: CGFloat = 28
        static let progressRing: CGFloat = 14
        static let progressRingLine: CGFloat = 2
        static let statTileMinHeight: CGFloat = 112
        static let emptyStateBadge: CGFloat = 56
        static let emptyStateTextWidth: CGFloat = 380
        static let bannerIcon: CGFloat = 30
        static let sheetWidth: CGFloat = 480
        static let snippetCardMinWidth: CGFloat = 300
        static let snippetCardMinHeight: CGFloat = 148
        static let progressBarWidth: CGFloat = 140
        static let firstRunVisualHeight: CGFloat = 52
        static let expansionEditorHeight: CGFloat = 120
        static let styleBubbleMinHeight: CGFloat = 76
        static let categoryIcon: CGFloat = 34
        /// Transcript lines shown before "Show more".
        static let transcriptLines = 3
        /// Roughly how many transcript characters fit on one line of a history row.
        static let transcriptCharsPerLine = 86
        static let recentCount = 5
        static let pageHeaderBottom: CGFloat = 20
    }
}

/// Press and disabled feedback shared by every custom control.
enum Interaction {
    static let pressedScale: CGFloat = 0.97
    static let disabledOpacity: Double = 0.45
    static let dimmedOpacity: Double = 0.55
}

extension Palette {
    /// Pressed surfaces and ghost buttons.
    static let surfacePressed = Color.adaptive(light: 0xE4E8F2, dark: 0x232B4D)
    /// Deprecated Ember-era names; they follow the primary fill now.
    static let emberHover = primaryFillHover
    static let emberPressed = primaryFillPressed
    /// Keycaps: a face a shade lighter than the surface and a darker lip below it.
    static let keyFace = Color.adaptive(light: 0xFFFFFF, dark: 0x2A3359)
    static let keyLip = Color.adaptive(light: 0x0E183C, lightAlpha: 0.20, dark: 0x000000, darkAlpha: 0.60)
    static let keyHighlight = Color.adaptive(light: 0xFFFFFF, lightAlpha: 1, dark: 0xFFFFFF, darkAlpha: 0.12)
    /// Selected filter chips are inked in, like a pressed key.
    static let chipSelected = Color.adaptive(light: 0x0E183C, dark: 0xEEF1FA)
    static let onChipSelected = Color.adaptive(light: 0xFFFFFF, dark: 0x0E183C)
}

extension Motion {
    /// Stat numerals rolling up when Home appears. Short enough to finish before a glance.
    static let countUp = Animation.easeOut(duration: 0.5)
    /// How long inline confirmations ("Copied") stay before fading.
    static let confirmation: Duration = .milliseconds(1400)
    /// How long a row revealed from elsewhere stays highlighted.
    static let highlight: Duration = .milliseconds(1800)
    /// How long a deletion can be undone before it's committed.
    static let undoWindow: Duration = .seconds(5)
    /// The first-run keycap pressing and releasing to act out "hold".
    static let demoKeyInterval: Duration = .milliseconds(1400)
}
