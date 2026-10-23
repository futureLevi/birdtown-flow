import AppKit
import SwiftUI

// MARK: - Birdtown Flow design language (the "Handoff" direction)
//
// Calm, large and legible. Light is the default; dark mode is a set of paired semantic tokens,
// not an inversion. Navy anchors the type and the primary actions (navy capsules, porcelain in
// dark mode); Signal blue (indigo-leaning, `Palette.accent`) marks interaction and selection;
// two small accents carry meaning: violet for tuning, Lab and polish, teal for vocabulary and
// the Dictionary. There is no full-spectrum decoration in the window. The logo's spectrum
// (`Spectrum`, `SpectrumOrb`) still means "your voice is live" on the recording pill, and the
// colour wheel stays there. Type is big on purpose: 19 pt for words you read (dictation,
// transcripts), 16-17 pt for interface text, nothing under 15 pt, 34 pt page titles. Surfaces
// are quiet: a hairline `line` edge, a barely-there panel shadow, 14 pt corners (8-9 pt on
// controls). Keyboard focus is a 3 pt outline 4 pt outside the control (`Layout.Focus`).
// Selection never relies on hue alone: a check, a radio mark, a marker bar or a heavier weight
// comes with the colour. Motion is springy but brief, and collapses to fades under Reduce Motion.
//
// Rules:
//  - Views never contain literal colours, sizes, radii or durations. Use these tokens; if a
//    token is missing, add it here.
//  - The spectrum is for live states only (`Spectrum`, `SpectrumOrb`, the pill) and the
//    Home hero artwork. Signal blue only for selection, focus, links and toggles. Violet and
//    teal only as small accents (icon tiles, badges, section tints), never for body text.
//    At most one primary (navy) action per view.
//  - Every animation goes through `Motion` so Reduce Motion is honoured everywhere.

enum Palette {
    /// Window background: a cool off-white, a deep navy in dark mode.
    static let canvas = Color.adaptive(light: 0xF6F7FB, dark: 0x0B1026)
    /// The main window's sidebar and the Settings card's section rail (flat). The main sidebar
    /// itself paints `sidebarGradient`.
    static let sidebar = Color.adaptive(light: 0xEDF1F8, dark: 0x10182F)
    /// Raised surfaces: cards, panels, popovers.
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x141A33)
    /// Hovered surface: a breath off `surface`, still visible on the canvas.
    static let surfaceHover = Color.adaptive(light: 0xEEF2FA, dark: 0x1B2342)
    /// Inset wells: text editors, prompt fields, code, empty states.
    static let sunken = Color.adaptive(light: 0xF8FAFF, dark: 0x0E1530)
    /// Editors and table headers: the page's quietest tint (same as `sunken`).
    static let editor = Color.adaptive(light: 0xF8FAFF, dark: 0x0E1530)
    /// The soft tile: keycaps, badges, chips, segmented tracks. Darker than the card in light
    /// mode, lighter in dark.
    static let soft = Color.adaptive(light: 0xEDF1F8, dark: 0x1C2444)
    /// The chosen row in the sidebar and the Settings rail: Signal blue's tint (with a marker
    /// bar and accent text, so never hue alone).
    static let selection = Color.adaptive(light: 0xEAF0FF, dark: 0x222E56)
    /// A sidebar or rail row under the pointer.
    static let sidebarHover = Color.adaptive(light: 0xFFFFFF, dark: 0x141A33)
    /// The toolbar's own fill: halfway between surface and canvas.
    static let toolbar = Color.adaptive(light: 0xFCFCFE, dark: 0x11162E)
    /// The sidebar's quiet diagonal wash, top to bottom.
    static let sidebarGradient: [Gradient.Stop] = [
        .init(color: .adaptive(light: 0xF4F7FD, dark: 0x17213C), location: 0),
        .init(color: .adaptive(light: 0xEDF2FA, dark: 0x10182F), location: 0.65),
        .init(color: .adaptive(light: 0xEAF1F6, dark: 0x10182F), location: 1),
    ]
    /// The wash runs slightly across the column, not straight down.
    static let sidebarGradientStart = UnitPoint(x: 0.3, y: 0)
    static let sidebarGradientEnd = UnitPoint(x: 0.7, y: 1)
    /// 1 px separators and card borders.
    static let hairline = Color.adaptive(light: 0xDCE2EF, dark: 0x303B5B)
    /// Control borders (inputs, secondary buttons, keycaps) and unselected radio marks. Clears
    /// 3:1 against its surface.
    static let hairlineStrong = Color.adaptive(light: 0x838CA5, dark: 0x7E89AB)
    /// The same value under its handoff name, for control outlines.
    static let control = hairlineStrong

    /// Primary text: deep navy.
    static let ink = Color.adaptive(light: 0x0E183C, dark: 0xEEF1FA)
    /// The few words that lead a screen: greeting, big numbers. Same as `ink`.
    static let heading = Color.adaptive(light: 0x0E183C, dark: 0xEEF1FA)
    /// Secondary text: descriptions, labels, metadata.
    static let inkSecondary = Color.adaptive(light: 0x4A5478, dark: 0xB0B8D3)
    /// Tertiary text: placeholders, disabled, timestamps. Still clears 4.5:1 on canvas and
    /// surface in both themes, because people read what it carries.
    static let inkTertiary = Color.adaptive(light: 0x626C89, dark: 0xA0AAC8)
    /// Quiet icons (chevrons, the sidebar's hide button). Icons only, never text.
    static let icon = Color.adaptive(light: 0x838CA5, dark: 0x7E89AB)

    /// The primary action: a navy capsule in light mode, porcelain in dark.
    static let primaryFill = Color.adaptive(light: 0x0E183C, dark: 0xEEF1FA)
    static let primaryFillHover = Color.adaptive(light: 0x233567, dark: 0xFFFFFF)
    static let primaryFillPressed = Color.adaptive(light: 0x08102A, dark: 0xD3D9EC)
    /// Text and icons on `primaryFill`.
    static let onPrimary = Color.adaptive(light: 0xFFFFFF, dark: 0x0E183C)

    /// Signal blue: selection, focus, toggles, checkmarks, links.
    static let accent = Color.adaptive(light: 0x4256F0, dark: 0x93A0FF)
    static let accentHover = Color.adaptive(light: 0x3546CD, dark: 0xB2BBFF)
    /// Signal blue's tint: selected backgrounds, soft buttons, badges.
    static let accentSoft = Color.adaptive(light: 0xEAF0FF, dark: 0x222E56)
    /// A selected control's hairline edge: the accent at low strength.
    static let accentEdge = Color.adaptive(light: 0x4256F0, lightAlpha: 0.15, dark: 0x93A0FF, darkAlpha: 0.22)
    /// Signal blue as text (links, "Add a key..."): already 4.5:1 on canvas and surface.
    static let accentInk = Color.adaptive(light: 0x4256F0, dark: 0x93A0FF)
    /// Text drawn on a blue fill.
    static let onAccent = Color.adaptive(light: 0xFFFFFF, dark: 0x0E183C)
    /// The keyboard focus ring.
    static let focus = Color.adaptive(light: 0x4256F0, dark: 0xB2BBFF)

    /// Violet, a small accent for tuning: the Lab, polish, "Polished" badges.
    static let violet = Color.adaptive(light: 0x6945B5, dark: 0xB9A6F4)
    static let violetSoft = Color.adaptive(light: 0xF0EBFB, dark: 0x302647)
    /// Teal, a small accent for vocabulary: the Dictionary and what it knows.
    static let teal = Color.adaptive(light: 0x176B70, dark: 0x85D1CB)
    static let tealSoft = Color.adaptive(light: 0xE5F3F1, dark: 0x142F38)

    static let success = Color.adaptive(light: 0x216D50, dark: 0x94D6B5)
    static let successSoft = Color.adaptive(light: 0xE9F4EE, dark: 0x22382E)
    static let warning = Color.adaptive(light: 0x9B4C21, dark: 0xEFB489)
    static let warningSoft = Color.adaptive(light: 0xFFF0E5, dark: 0x3F3025)
    static let danger = Color.adaptive(light: 0xAE344C, dark: 0xFFA3B8)
    static let dangerSoft = Color.adaptive(light: 0xFCECF0, dark: 0x422931)
    /// Where a History search matched: amber like the system's find highlight, strong enough
    /// to read on a selected row's Signal blue wash.
    static let searchMatch = Color.adaptive(light: 0xB7791F, lightAlpha: 0.22, dark: 0xF0B04A, darkAlpha: 0.28)

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
        /// The record light in the pill.
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
    /// Page titles: "History", "Good evening, Levi". 34 pt.
    static let display = Font.system(size: 34, weight: .semibold)
    /// Section titles inside a page ("Recent dictation"), sheet titles. 21 pt.
    static let title = Font.system(size: 21, weight: .semibold)
    /// A heading a step above a section: panels, dialogs, Settings panes. 23 pt.
    static let sectionTitle = Font.system(size: 23, weight: .semibold)
    /// Big numbers in stat summaries.
    static let numeral = Font.system(size: 30, weight: .semibold).monospacedDigit()
    /// Card and row headings. 16 pt.
    static let headline = Font.system(size: 16, weight: .semibold)
    /// Interface text: labels, buttons, fields. 16 pt.
    static let body = Font.system(size: 16)
    static let bodyEmphasis = Font.system(size: 16, weight: .medium)
    /// Interface text that leads a row: Dictionary terms, Settings row titles, page
    /// descriptions. 17 pt.
    static let bodyLarge = Font.system(size: 17)
    static let bodyLargeEmphasis = Font.system(size: 17, weight: .medium)
    /// Dictated text: the user's own words, 19 pt on a 1.6 line height (`transcriptLine`).
    static let transcript = Font.system(size: 19)
    /// The same words opened up in a detail view. 21 pt.
    static let transcriptLarge = Font.system(size: 21)
    /// Metadata: times, durations, helper text. Never below 15 pt, except in list rows (`List`).
    static let callout = Font.system(size: 15)
    static let caption = Font.system(size: 15, weight: .medium)
    /// A small label above a group of rows. Sentence case at 15 pt; the old tracked
    /// uppercase would shout at this size.
    static let eyebrow = Font.system(size: 15, weight: .semibold)
    /// Keycaps and shortcuts.
    static let keycap = Font.system(size: 15, weight: .medium)
    static let mono = Font.system(size: 15, design: .monospaced)
    /// HUD labels.
    static let hud = Font.system(size: 12, weight: .medium)
    static let hudNumeral = Font.system(size: 12, weight: .medium).monospacedDigit()
    /// A monogram standing in for an app icon that couldn't be loaded.
    static func monogram(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// The old compact scale, for the surfaces the redesign leaves alone: onboarding, the
    /// menu bar window and the documentation sheets in the snapshots. Same names as above.
    enum Compact {
        static let display = Font.system(size: 28, weight: .bold)
        static let title = Font.system(size: 19, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyEmphasis = Font.system(size: 13, weight: .medium)
        static let transcript = Font.system(size: 15)
        static let transcriptLarge = Font.system(size: 17)
        static let callout = Font.system(size: 12)
        static let caption = Font.system(size: 11, weight: .medium)
        static let eyebrow = Font.system(size: 10.5, weight: .semibold)
        static let keycap = Font.system(size: 12, weight: .medium)
        static let mono = Font.system(size: 12, design: .monospaced)
    }

    /// List rows a step below the interface scale, at Levi's request: History's rows, Home's
    /// Recent dictation and the Dictionary table. Dictated words 17 pt instead of 19, row
    /// headings and text 15, terms 16, times and details 14.
    enum List {
        static let transcript = Font.system(size: 17)
        static let headline = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 15)
        static let bodyEmphasis = Font.system(size: 15, weight: .medium)
        /// A Dictionary term (was `bodyLarge`, 17 pt).
        static let term = Font.system(size: 16)
        static let termEmphasis = Font.system(size: 16, weight: .medium)
        static let callout = Font.system(size: 14)
        static let caption = Font.system(size: 14, weight: .medium)
        static let eyebrow = Font.system(size: 14, weight: .semibold)
    }
}

enum Tracking {
    static let eyebrow: CGFloat = 0.8
    /// Page titles (34 pt).
    static let display: CGFloat = -1.1
    /// Section titles (21-23 pt).
    static let title: CGFloat = -0.55

    /// Tracking for `Typography.Compact`.
    enum Compact {
        static let display: CGFloat = -0.5
        static let title: CGFloat = -0.25
    }
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
    /// Page padding inside the detail column: the content inset.
    static let page: CGFloat = 40
    /// Line spacing for transcript text: 19 pt on a 1.6 line height is 30 pt a line, and
    /// the system's own line is about 23, so this adds the rest.
    static let transcriptLine: CGFloat = 7
}

enum Radius {
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    /// Controls: buttons, inputs, icon buttons.
    static let control: CGFloat = 8
    /// Fields and nav rows, a hair rounder than buttons.
    static let field: CGFloat = 9
    static let m: CGFloat = 10
    /// Cards, panels, tables, list frames.
    static let l: CGFloat = 14
    /// Dialogs, the window's own corners.
    static let xl: CGFloat = 20
}

enum Layout {
    static let sidebarWidth: CGFloat = 220
    /// The detail column's widest content (a page's inner width at the 40 pt inset).
    static let contentMaxWidth: CGFloat = 1120
    static let windowMinWidth: CGFloat = 860
    static let windowMinHeight: CGFloat = 560
    static let windowIdealWidth: CGFloat = 1180
    static let windowIdealHeight: CGFloat = 760
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

extension Layout {
    /// Keyboard focus: a 3 pt outline, 4 pt outside the control's edge (`flowFocusRing`).
    enum Focus {
        static let width: CGFloat = 3
        static let offset: CGFloat = 4
    }

    /// The window toolbar: page title on the left, Search history and status on the right.
    /// 66 pt tall, level with the traffic lights' row in the sidebar.
    enum Toolbar {
        static let height: CGFloat = 66
        /// Side padding, the same as a page's content inset.
        static let inset: CGFloat = 40
        /// With the sidebar hidden the title steps past the traffic lights and Show sidebar.
        static let hiddenLeading: CGFloat = 124
        /// Between the toolbar's right-hand items.
        static let gap: CGFloat = 24
        /// Between an item's icon or dot and its label.
        static let itemSpacing: CGFloat = 8
        static let searchIcon: CGFloat = 15
    }
}

enum Elevation {
    struct Shadow { let color: Color; let radius: CGFloat; let y: CGFloat }
    /// Cards and panels at rest: a hairline carries the edge, with the faintest lift under it.
    static let card = Shadow(
        color: Color.adaptive(light: 0x172653, lightAlpha: 0.04, dark: 0x000000, darkAlpha: 0.10),
        radius: 10,
        y: 3
    )
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
    /// The pill's body: the icon's navy, lit from the top (the pill is not part of the redesign).
    static let fillTop = Color(hex: 0x1C2B57)
    static let fillBottom = Color(hex: 0x0E183B)
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
    static let hudKeycap = Font.system(size: 10.5, weight: .semibold)
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
    static let hero = Font.system(size: 40, weight: .bold)
    /// The paragraph under an onboarding title: a step larger than body, for calm reading.
    static let lead = Font.system(size: 14)
    /// Recent dictations in the menu bar window: the user's words, at menu scale.
    static let transcriptSmall = Font.system(size: 13)
    /// The symbol inside an onboarding step's glyph.
    static let stepGlyph = Font.system(size: 22, weight: .regular)
    /// Big keycaps in the shortcut picker.
    static let keycapLarge = Font.system(size: 19, weight: .medium)
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
        static let hairline: CGFloat = 1
        /// The spectrum's light behind the welcome icon: an orb wider than the icon, faded out
        /// from the tile's edge (`heroGlowInner`) to its rim, faint enough that the icon stays
        /// the hero. Painted, not blurred, so snapshots show what people see.
        static let heroOrb: CGFloat = 216
        static let heroGlowInner: CGFloat = 46
        static let heroOrbOpacityLight: Double = 0.5
        static let heroOrbOpacityDark: Double = 0.62
    }
}

extension Elevation {
    /// No shadow, for marks drawn too small for one to read as anything but a smudge.
    static let flat = Shadow(color: .clear, radius: 0, y: 0)
    /// The Settings card floating over the dimmed main window.
    static let modal = Shadow(color: .black.opacity(0.22), radius: 40, y: 16)
}

extension Palette {
    /// Dims the main window behind the Settings card.
    static let scrim = Color.adaptive(light: 0x0E183C, lightAlpha: 0.34, dark: 0x000000, darkAlpha: 0.55)
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
    /// Seconds into a live orb's motion that snapshots draw, so frames are deterministic.
    static let snapshotOrbPhase: Double = 2.5
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

    /// Label above a group of rows: 15 pt, semibold, sentence case.
    func eyebrowStyle() -> some View {
        self.font(Typography.eyebrow)
            .foregroundStyle(Palette.inkSecondary)
    }

    /// The old small, uppercase, tracked label, for the menu bar window.
    func compactEyebrowStyle() -> some View {
        self.font(Typography.Compact.eyebrow)
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
        /// Buttons: 42 pt regular, 35 pt small, 48 pt large (the handoff's hit areas).
        static let buttonHeight: CGFloat = 42
        static let buttonHeightSmall: CGFloat = 35
        static let buttonHeightLarge: CGFloat = 48
        /// Side padding inside a button; the navy capsule takes a little more than the rest.
        static let buttonPadding: CGFloat = 15
        static let buttonPaddingPrimary: CGFloat = 19
        static let buttonPaddingSmall: CGFloat = 11
        static let buttonPaddingLarge: CGFloat = 24
        static let iconButton: CGFloat = 36
        static let chipHeight: CGFloat = 34
        static let searchFieldHeight: CGFloat = 44
        static let searchFieldWidth: CGFloat = 320
        static let keyCapHeight: CGFloat = 27
        static let keyCapMinWidth: CGFloat = 27
        static let keyCapHeightLarge: CGFloat = 48
        static let keyCapMinWidthLarge: CGFloat = 48
        /// The darker lip along a keycap's bottom edge: it's what makes it read as a key.
        static let keyCapLip: CGFloat = 2
        static let keyCapLipLarge: CGFloat = 3
        static let statusDot: CGFloat = 7
        static let rowIcon: CGFloat = 31
        static let progressRing: CGFloat = 14
        static let progressRingLine: CGFloat = 2
        static let emptyStateBadge: CGFloat = 56
        static let emptyStateTextWidth: CGFloat = 460
        static let bannerIcon: CGFloat = 34
        static let sheetWidth: CGFloat = 570
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
        static let pageHeaderBottom: CGFloat = 29
        /// A page header's symbol tile and its gap to the title; the description's measure.
        static let pageHeaderSymbol: CGFloat = 52
        static let pageHeaderSymbolGap: CGFloat = 17
        static let pageSubtitleWidth: CGFloat = 640
        /// The logo's bars in the first-run "speak" step and in empty states.
        static let brandMarkLarge: CGFloat = 40
        static let brandMarkSmall: CGFloat = 22
        /// An input's own border while focused (onboarding and Lab fields draw it inside the
        /// field). Controls that use `flowFocusRing` get the 3 pt `Layout.Focus` ring instead.
        static let focusRing: CGFloat = 1.5
        /// `AppIcon`'s monogram tile, as fractions of the icon's size: corner radius, letter
        /// size, and the inset that matches the margin real app icons leave around their tile.
        static let monogramCornerRatio: CGFloat = 0.24
        static let monogramFontRatio: CGFloat = 0.46
        static let monogramInsetRatio: CGFloat = 0.06
        /// Model download progress (`SpectrumProgressBar`).
        static let progressBarHeight: CGFloat = 4
        /// The logo's bars beside a snippet's trigger.
        static let triggerMark: CGFloat = 10
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
    static let surfacePressed = Color.adaptive(light: 0xE3E9F6, dark: 0x222E56)
    /// Keycaps: a surface-coloured face with a control-coloured edge and a heavier lip below.
    static let keyFace = Color.adaptive(light: 0xFFFFFF, dark: 0x141A33)
    static let keyLip = Color.adaptive(light: 0x838CA5, dark: 0x7E89AB)
    /// Style's sample message bubbles: a step darker than the card in light mode and a step
    /// lighter in dark, like chat bubbles.
    static let bubble = Color.adaptive(light: 0xEDF1F8, dark: 0x1C2444)
    /// The bubble on a chosen card's Signal blue wash.
    static let bubbleOnSelection = Color.adaptive(light: 0xFFFFFF, dark: 0x2B3868)
    /// Small filled marks that sit on a card: neutral badges, monogram tiles, icon tiles.
    /// Same as `soft`.
    static let chip = Color.adaptive(light: 0xEDF1F8, dark: 0x1C2444)
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

extension Layout {
    /// The main window's sidebar: flush, 234 pt, a quiet wash off the canvas, under the
    /// traffic lights.
    enum Sidebar {
        static let width: CGFloat = 234
        /// The traffic lights' row above the wordmark: the toolbar's height, so their
        /// baselines line up across the window.
        static let topInset: CGFloat = Layout.Toolbar.height
        /// Rows sit 15 pt in from the edges, leaving room for the marker bar and the 3 pt
        /// focus ring (which would clip at the scroll view's edge otherwise).
        static let horizontalPadding: CGFloat = 15
        static let bottomPadding: CGFloat = 20
        static let rowHeight: CGFloat = 46
        static let rowRadius: CGFloat = Radius.field
        static let rowPadding: CGFloat = 13
        static let rowSpacing: CGFloat = 12
        /// Between nav rows.
        static let rowGap: CGFloat = 5
        /// The column the icons sit in, so labels line up whatever the symbol's width.
        static let iconColumn: CGFloat = 22
        /// The app icon beside the name (its tile fills about 80 % of this).
        static let logo: CGFloat = 48
        static let wordmarkSpacing: CGFloat = 8
        static let wordmarkInset: CGFloat = 5
        static let wordmarkBottom: CGFloat = 27
        /// The selected row's marker bar, in the margin left of the row.
        static let markerWidth: CGFloat = 3
        static let markerInset: CGFloat = 14
        static let markerOffset: CGFloat = 6
        /// The divider and "Workspace" label.
        static let dividerInset: CGFloat = 12
        static let dividerVertical: CGFloat = 20
        static let labelBottom: CGFloat = 9
        /// The "fn  Hold to dictate" line under Settings.
        static let hintTop: CGFloat = 20
        static let hintInset: CGFloat = 12
        static let hintSpacing: CGFloat = 9
        /// The Hide sidebar button, top right of the sidebar, level with the traffic lights.
        static let hideButton: CGFloat = 28
        static let hideButtonRadius: CGFloat = Radius.control
        static let hideButtonTop: CGFloat = 19
        static let hideButtonTrailing: CGFloat = 14
        /// With the sidebar hidden, Show sidebar sits right of the traffic lights.
        static let showButtonLeading: CGFloat = 80
    }
}

extension Typography {
    /// An empty state's headline. 19 pt.
    static let emptyTitle = Font.system(size: 19, weight: .semibold)
    /// The symbol in a page header's tile.
    static let pageSymbol = Font.system(size: 26, weight: .regular)
    /// The nav rows: 16 pt, heavier when chosen (never hue alone).
    static let sidebarRow = Font.system(size: 16, weight: .medium)
    static let sidebarRowSelected = Font.system(size: 16, weight: .semibold)
    /// The section icons, drawn to sit in a 22 pt column like the design's 21 pt line icons.
    static let sidebarIcon = Font.system(size: 17, weight: .regular)
    static let sidebarIconSelected = Font.system(size: 17, weight: .semibold)
    /// "Workspace" above the Lab, and the History count.
    static let sidebarLabel = Font.system(size: 15)
    static let sidebarCount = Font.system(size: 15).monospacedDigit()
    /// The app's name beside its icon at the top of the sidebar.
    static let wordmark = Font.system(size: 18, weight: .semibold)
    /// The toolbar's page title, Search history and status.
    static let toolbarTitle = Font.system(size: 15, weight: .medium)
    static let toolbarItem = Font.system(size: 15)
    /// The unit beside a stat numeral ("words", "wpm").
    static let statUnit = Font.system(size: 15)
    /// The stat's name beside its badge.
    static let statLabel = Font.system(size: 15, weight: .medium)
    static let statCaption = Font.system(size: 15).monospacedDigit()
    static let statGlyph = Font.system(size: 11.5, weight: .semibold)
    /// "Recent dictation" on Home, and a Settings group's title.
    static let groupTitle = Font.system(size: 17, weight: .semibold)
    static let link = Font.system(size: 15, weight: .semibold)
    /// A Settings pane's title in its header.
    static let paneTitle = Font.system(size: 23, weight: .semibold)
    static let settingsRowTitle = Font.system(size: 17, weight: .medium)
    static let settingsRowDetail = Font.system(size: 15)
}
