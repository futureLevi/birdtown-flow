import AppKit
import SwiftUI

// MARK: - Birdtown Flow design language ("Mono v2")
//
// Calm and nearly colourless, with the logo's navy as a whisper in every grey: near-black navy
// ink on white, a soft grey sidebar, and a night navy-charcoal in dark mode. Surfaces are flat:
// soft grey fills and hairlines instead of shadows and boxes. The colour lives in a few small,
// deliberate places, all taken from the logo's disc: the sidebar's icons walk its colour wheel
// (`Palette.Wheel`), each Home stat wears its own badge and glow (`Palette.Stat`), and Signal
// blue, the orb's own blue, is the accent for selection, focus, links and switches. Primary actions are navy pills
// (porcelain in dark mode), like the logo's tile and ring. The spectrum itself, the logo's
// disc, means "your voice is live": the recording orb, the thinking ring, download progress and
// the onboarding hero. Its one resting use is Home's Voiceprint hero, a voice drawn as artwork
// on the icon's navy. SF Pro throughout: semibold for titles and big numbers, regular for
// everything you read, including your own words. Motion is springy but brief, and collapses to
// fades under Reduce Motion.
//
// Rules:
//  - Views never contain literal colours, sizes, radii or durations. Use these tokens; if a
//    token is missing, add it here.
//  - Spectrum only for live states (`Spectrum`, `SpectrumOrb`) and the Home hero
//    (`VoiceprintArt`). Signal blue only for selection, focus, links and toggles. Wheel
//    colours only on icons (sidebar sections, Settings sections, Home stat badges), never on
//    text or backgrounds. At most one primary (navy) action per view.
//  - Every animation goes through `Motion` so Reduce Motion is honoured everywhere.

enum Palette {
    /// Window background: white, a night navy-charcoal in dark mode.
    static let canvas = Color.adaptive(light: 0xFFFFFF, dark: 0x1B1D24)
    /// The main window's sidebar and the Settings card's section rail: a step off the canvas.
    static let sidebar = Color.adaptive(light: 0xF7F8FA, dark: 0x14161B)
    /// Raised surfaces: cards, popovers. White with a hairline in light mode; a breath lighter
    /// than the canvas in dark.
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x1F2128)
    /// Hovered surface.
    static let surfaceHover = Color.adaptive(light: 0xF3F5F8, dark: 0x262932)
    /// Inset wells: text inputs, code, empty states.
    static let sunken = Color.adaptive(light: 0xF3F5F8, dark: 0x14161B)
    /// The soft grey tile: Home's stat cards, keycaps, badges, chips.
    static let soft = Color.adaptive(light: 0xF3F5F8, dark: 0x262932)
    /// The chosen row in the sidebar and the Settings rail: grey, never coloured.
    static let selection = Color.adaptive(light: 0xEAEDF3, dark: 0x262932)
    /// A sidebar or rail row under the pointer: half a step toward `selection`.
    static let sidebarHover = Color.adaptive(light: 0xF0F2F6, dark: 0x1D2026)
    /// 1px separators and card borders, tinted navy.
    static let hairline = Color.adaptive(light: 0x0E1426, lightAlpha: 0.08, dark: 0xE8EAF0, darkAlpha: 0.08)
    /// Stronger border for focused inputs and selected cards.
    static let hairlineStrong = Color.adaptive(light: 0x0E1426, lightAlpha: 0.16, dark: 0xE8EAF0, darkAlpha: 0.18)

    /// Primary text: near-black with the logo's navy in it.
    static let ink = Color.adaptive(light: 0x0E1426, dark: 0xE8EAF0)
    /// The few words that lead a screen: the greeting, the stat numbers. Ink in light mode,
    /// pure white in dark.
    static let heading = Color.adaptive(light: 0x0E1426, dark: 0xFFFFFF)
    /// Secondary text: metadata, descriptions.
    static let inkSecondary = Color.adaptive(light: 0x596072, dark: 0xA3A8B5)
    /// Tertiary text: placeholders, disabled, timestamps. Still clears 4.5:1 on canvas, surface
    /// and hovered surface in both themes, because people read what it carries.
    static let inkTertiary = Color.adaptive(light: 0x666C7E, dark: 0x9197A6)
    /// Quiet icons (chevrons, the sidebar's hide button). Icons only, never text.
    static let icon = Color.adaptive(light: 0x8A90A0, dark: 0x8C92A1)

    /// The primary action: a navy pill in light mode, porcelain in dark (the logo's tile and ring).
    static let primaryFill = Color.adaptive(light: 0x0E183C, dark: 0xE8EAF0)
    static let primaryFillHover = Color.adaptive(light: 0x1D2B5E, dark: 0xFFFFFF)
    static let primaryFillPressed = Color.adaptive(light: 0x08102A, dark: 0xD2D5DE)
    /// Text and icons on `primaryFill`.
    static let onPrimary = Color.adaptive(light: 0xFFFFFF, dark: 0x0E1426)

    /// Signal blue, the orb's own blue: selection rings, focus rings, toggles, checkmarks.
    static let accent = Color.adaptive(light: 0x3082F8, dark: 0x4C93FA)
    /// Signal blue at low strength: selected backgrounds, badges.
    static let accentSoft = Color.adaptive(light: 0x3082F8, lightAlpha: 0.10, dark: 0x4C93FA, darkAlpha: 0.18)
    /// Signal blue as text (links, "Add a key…"): deep enough to read at 4.5:1.
    static let accentInk = Color.adaptive(light: 0x2462BA, dark: 0x6AA6FB)
    /// Text drawn on a blue fill.
    static let onAccent = Color.white

    static let success = Color.adaptive(light: 0x1E8F63, dark: 0x4FD39A)
    static let successSoft = Color.adaptive(light: 0x1E8F63, lightAlpha: 0.10, dark: 0x4FD39A, darkAlpha: 0.16)
    static let warning = Color.adaptive(light: 0xB7791F, dark: 0xF0B04A)
    static let warningSoft = Color.adaptive(light: 0xB7791F, lightAlpha: 0.10, dark: 0xF0B04A, darkAlpha: 0.15)
    static let danger = Color.adaptive(light: 0xD03A4E, dark: 0xFF6B7A)
    static let dangerSoft = Color.adaptive(light: 0xD03A4E, lightAlpha: 0.09, dark: 0xFF6B7A, darkAlpha: 0.15)
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
    /// Page titles: "History", "Good evening, Levi".
    static let display = Font.system(size: 28, weight: .bold)
    /// Section titles inside a page, sheet titles.
    static let title = Font.system(size: 19, weight: .semibold)
    /// Big numbers in stat tiles.
    static let numeral = Font.system(size: 24, weight: .semibold).monospacedDigit()
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
    static let keycap = Font.system(size: 12, weight: .medium)
    static let mono = Font.system(size: 12, design: .monospaced)
    /// HUD labels.
    static let hud = Font.system(size: 12, weight: .medium)
    static let hudNumeral = Font.system(size: 12, weight: .medium).monospacedDigit()
    /// A monogram standing in for an app icon that couldn't be loaded.
    static func monogram(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

enum Tracking {
    static let eyebrow: CGFloat = 0.8
    static let display: CGFloat = -0.5
    static let title: CGFloat = -0.25
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
    struct Shadow { let color: Color; let radius: CGFloat; let y: CGFloat }
    /// Cards at rest are flat (a hairline carries the edge), so this is no shadow at all.
    static let card = Shadow(color: .clear, radius: 0, y: 0)
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
    /// The pill's body: the icon's navy, lit from the top (Mono v2's navy pill).
    static let fillTop = Color(hex: 0x1C2B57)
    static let fillBottom = Color(hex: 0x0E183B)
    /// Stop in hands-free: a warm-white disc holding a navy square, like the logo's ring
    /// around its tile. It darkens a little under the pointer.
    static let stopFill = Color(hex: 0xFEFCF8)
    static let stopGlyph = Color(hex: 0x0E183B)
    static let stopHover = Color(hex: 0x0E183B, alpha: 0.10)
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
    static let scrim = Color.adaptive(light: 0x0E1426, lightAlpha: 0.28, dark: 0x000000, darkAlpha: 0.55)
}

extension Layout {
    /// Settings as a card over the main window: a column of sections, then a pane as wide
    /// as the old Settings window. In a smaller window the card shrinks and its pane scrolls.
    enum SettingsModal {
        static let sidebarWidth: CGFloat = 208
        static let rowHeight: CGFloat = 32
        static let size = CGSize(
            width: sidebarWidth + Setup.hairline + Layout.settingsWidth,
            height: Setup.settingsHeight
        )
    }
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
        /// The logo's bars in the first-run "speak" step and in empty states.
        static let brandMarkLarge: CGFloat = 40
        static let brandMarkSmall: CGFloat = 22
        /// Focused inputs: a Signal blue ring this wide.
        static let focusRing: CGFloat = 1.5
        /// Space between a focused control's edge and its focus ring (`flowFocusRing`), so the
        /// ring stays distinct from a selected chip's Signal blue border.
        static let focusRingGap: CGFloat = 2
        /// `AppIcon`'s monogram tile, as fractions of the icon's size: corner radius, letter
        /// size, and the inset that matches the margin real app icons leave around their tile.
        static let monogramCornerRatio: CGFloat = 0.24
        static let monogramFontRatio: CGFloat = 0.46
        static let monogramInsetRatio: CGFloat = 0.06
        /// Model download progress (`SpectrumProgressBar`).
        static let progressBarHeight: CGFloat = 4
        /// The logo's bars beside a snippet's trigger.
        static let triggerMark: CGFloat = 10
        /// The app icon in the sidebar wordmark: its tile (about 80 % of this) fills the
        /// wordmark's 28 pt slot.
        static let sidebarLogo: CGFloat = 35
    }

    /// The Lab: polish configurations, their editor, the test text and results.
    enum Lab {
        static let listWidth: CGFloat = 210
        static let instructionsHeight: CGFloat = 260
        static let sampleHeight: CGFloat = 88
        static let fieldHeight: CGFloat = 30
        static let appFieldWidth: CGFloat = 150
        static let providerWidth: CGFloat = 190
        static let styleWidth: CGFloat = 130
        static let categoryWidth: CGFloat = 180
        static let modelMenuWidth: CGFloat = 24
        /// The refused reply, shown on request, scrolls past this.
        static let replyMaxHeight: CGFloat = 160
    }
}

extension Typography {
    /// The app's name beside its icon at the top of the sidebar.
    static let wordmark = Font.system(size: 15, weight: .semibold)
    /// The unit beside a stat numeral ("words", "wpm").
    static let statUnit = Font.system(size: 13, weight: .medium)
}

/// Press and disabled feedback shared by every custom control.
enum Interaction {
    static let pressedScale: CGFloat = 0.97
    static let disabledOpacity: Double = 0.45
    static let dimmedOpacity: Double = 0.55
}

extension Palette {
    /// Pressed surfaces and ghost buttons.
    static let surfacePressed = Color.adaptive(light: 0xEAEDF3, dark: 0x2E313B)
    /// Keycaps: a face a shade lighter than the surface and a darker lip below it.
    static let keyFace = Color.adaptive(light: 0xFFFFFF, dark: 0x2E313B)
    static let keyLip = Color.adaptive(light: 0x0E1426, lightAlpha: 0.20, dark: 0x000000, darkAlpha: 0.60)
    static let keyHighlight = Color.adaptive(light: 0xFFFFFF, lightAlpha: 1, dark: 0xFFFFFF, darkAlpha: 0.12)
    /// Style's sample message bubbles: a step darker than the card in light mode and a step
    /// lighter in dark, like chat bubbles. `sunken` would read as a hole in dark mode.
    static let bubble = Color.adaptive(light: 0xF3F5F8, dark: 0x262932)
    /// The bubble on a chosen card's Signal blue wash.
    static let bubbleOnSelection = Color.adaptive(light: 0xFFFFFF, dark: 0x2F3C58)
    /// Small filled marks that sit on a card: neutral badges, monogram tiles, icon tiles. Same
    /// step as `bubble`: darker than the card in light mode, lighter in dark, so they read as
    /// raised. Keep `sunken` for inset wells (inputs, code, practice fields).
    static let chip = Color.adaptive(light: 0xF3F5F8, dark: 0x262932)
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

// MARK: - Home hero (Voiceprint)
//
// The navy band at the top of Home with the greeting on it, and the one place the spectrum
// appears at rest: a voice drawn as artwork (`VoiceprintArt`), which reads as the logo's big
// echo, not as a live state. It is the app icon's tile, so it stays navy in both appearances.

extension Palette {
    enum Hero {
        /// The icon tile's ground, top to bottom.
        static let ground: [Gradient.Stop] = [
            .init(color: Color(hex: 0x263B6E), location: 0),
            .init(color: Color(hex: 0x203569), location: 0.10),
            .init(color: Color(hex: 0x0E183B), location: 0.45),
            .init(color: Color(hex: 0x091231), location: 1),
        ]
        /// A faint inner edge, so the tile reads as an object on midnight navy.
        static let edge = Color.white.opacity(0.06)
        static let ink = Color.white
        static let inkSecondary = Color.white.opacity(0.72)
        /// The logo's warm-white bars before the hint.
        static let mark = Color(hex: 0xFEFCF8)
        /// The shortcut's keycap on navy.
        static let keyFill = Color.white.opacity(0.12)
        static let keyStroke = Color.white.opacity(0.22)
        /// The lift under the hero on a light page (none in dark, where it would be lost).
        static let shadow = Color(hex: 0x091231)
    }
}

extension Layout {
    enum Hero {
        static let height: CGFloat = 150
        /// The width the art was designed at. Wider heroes add calm room on the left; narrower
        /// ones squeeze the art horizontally, so the voice always ends at the right edge.
        static let designWidth: CGFloat = 660
        static let cornerRadius: CGFloat = 18
        static let edge: CGFloat = 1
        /// The greeting's left inset and the gap between it and the hint.
        static let textInset: CGFloat = 28
        static let textSpacing: CGFloat = 8
        /// Where, in the design's space, the greeting and the hint should end: the voice is
        /// only a whisper until about here, and full strength past it.
        static let greetingEndX: CGFloat = 360
        static let hintEndX: CGFloat = 300
        /// The logo's bars before the hint, and the gaps around the shortcut keycap.
        static let markHeight: CGFloat = 12
        static let hintSpacing: CGFloat = 8
        static let keySpacing: CGFloat = 5
        static let keyHeight: CGFloat = 20
        static let keyPadding: CGFloat = 6
        static let keyRadius: CGFloat = 6
    }
}

extension Typography {
    /// The hint under the greeting on the hero, a step up from body so it holds its own on navy.
    static let heroHint = Font.system(size: 14.5)
    static let heroKey = Font.system(size: 11.5, weight: .medium)
}

extension Elevation {
    /// The hero's lift on a light page: a tight contact shadow and a soft, wider one.
    static let heroContact = Shadow(color: Palette.Hero.shadow.opacity(0.10), radius: 1, y: 1)
    static let heroLift = Shadow(color: Palette.Hero.shadow.opacity(0.14), radius: 14, y: 10)
}

extension Motion {
    /// The hero redraws at most this often while it moves (never between sweeps).
    static let heroFrameInterval: Double = 1.0 / 60.0
    /// The first Shimmer sweep starts this long after the opening ends; later ones follow
    /// every `VoiceprintMotion.sweepInterval`.
    static let heroFirstSweepDelay: Double = 1.2
    /// The glows behind the loudest syllables rising with the opening (easeOutCubic).
    static let heroGlowRise = Animation.timingCurve(0.33, 1, 0.68, 1, duration: 0.85)
}

// MARK: - Mono v2: the sidebar, the Settings rail and Home's stats
//
// The few places colour lives at rest. The sidebar's icons walk the logo's colour wheel from
// the top (Home orange through Settings purple), the Settings rail follows the same order, and
// each Home stat wears a small badge built like the app icon plus a soft glow in its corner.
// Light mode takes deeper shades so the icons hold their own on pale grey.

extension Palette {
    /// The logo disc's colour wheel, in the order the sidebar walks it.
    enum Wheel {
        static let orange = Color.adaptive(light: 0xE8701F, dark: 0xFEA964)
        static let gold = Color.adaptive(light: 0xD08C00, dark: 0xF6CB4C)
        static let green = Color.adaptive(light: 0x1FA36A, dark: 0x3CCB8A)
        static let cyan = Color.adaptive(light: 0x1693C4, dark: 0x2FB8E6)
        static let blue = Color.adaptive(light: 0x3082F8, dark: 0x4C93FA)
        static let violet = Color.adaptive(light: 0x6F54FB, dark: 0x8B76FC)
        static let purple = Color.adaptive(light: 0xB348ED, dark: 0xC26CF2)

        /// The wheel from the top, for lists that walk it in order.
        static let walk: [Color] = [orange, gold, green, cyan, blue, violet, purple]
    }

    /// A Home stat's colour: a badge lit from the top like the app icon, and a glow in the
    /// card's top-right corner.
    struct StatTone {
        let badgeTop: Color
        let badgeBottom: Color
        let glow: Color

        static let blue = StatTone(top: 0x5A9CFB, bottom: 0x2B6FE6, glow: 0x3082F8)
        static let green = StatTone(top: 0x4BD394, bottom: 0x18A066, glow: 0x3CCB8A)
        static let orange = StatTone(top: 0xFFA25C, bottom: 0xEA6A1E, glow: 0xF78C46)
        static let purple = StatTone(top: 0xC77AF4, bottom: 0x9A3EE0, glow: 0xB348ED)

        private init(top: UInt32, bottom: UInt32, glow: UInt32) {
            badgeTop = Color(hex: top)
            badgeBottom = Color(hex: bottom)
            // A touch stronger on the dark tile, where the same light reads fainter.
            self.glow = Color.adaptive(light: glow, lightAlpha: 0.16, dark: glow, darkAlpha: 0.22)
        }
    }

    enum Stat {
        /// The badge's top-edge highlight and the small lift under it.
        static let badgeHighlight = Color.white.opacity(0.35)
        static let badgeShadow = Color(hex: 0x091231, alpha: 0.16)
        static let glyph = Color.white
    }
}

extension Layout {
    /// The main window's sidebar: flush, a step off the canvas, under the traffic lights.
    enum Sidebar {
        static let width: CGFloat = 244
        /// Room above the wordmark for the traffic lights.
        static let topInset: CGFloat = 52
        static let horizontalPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 10
        static let rowHeight: CGFloat = 32
        static let rowRadius: CGFloat = 10
        static let rowPadding: CGFloat = 10
        static let rowSpacing: CGFloat = 10
        /// The column the icons sit in, so labels line up whatever the symbol's width.
        static let iconColumn: CGFloat = 18
        static let wordmarkHeight: CGFloat = 28
        static let wordmarkBottom: CGFloat = 12
        /// "Admin" above the Lab.
        static let labelTop: CGFloat = 14
        static let labelBottom: CGFloat = 4
        /// The Hide sidebar button, top right of the sidebar, level with the traffic lights.
        static let hideButton: CGFloat = 28
        static let hideButtonRadius: CGFloat = 8
        static let hideButtonTop: CGFloat = 12
        static let hideButtonTrailing: CGFloat = 10
        /// With the sidebar hidden, Show sidebar sits right of the traffic lights, and the
        /// page starts below them.
        static let showButtonLeading: CGFloat = 80
        static let collapsedTopInset: CGFloat = 40
    }

    /// Home's column and its rhythm.
    enum Home {
        static let columnWidth: CGFloat = 660
        static let topPadding: CGFloat = 28
        static let statsTop: CGFloat = 20
        static let recentTop: CGFloat = 28
        static let recentHeaderBottom: CGFloat = 8
        static let bannersTop: CGFloat = 20
    }

    /// Home's stat cards: soft tiles, a badge, the number and a caption.
    enum Stat {
        static let spacing: CGFloat = 8
        static let padding: CGFloat = 14
        static let radius: CGFloat = 16
        static let badge: CGFloat = 24
        static let badgeRadius: CGFloat = 7
        static let labelSpacing: CGFloat = 8
        static let numberTop: CGFloat = 10
        static let unitSpacing: CGFloat = 4
        static let captionTop: CGFloat = 2
        /// The corner glow: an ellipse this wide and tall around the top-right corner, fading
        /// to nothing at `glowFade` of its radius.
        static let glowWidth: CGFloat = 150
        static let glowHeight: CGFloat = 110
        static let glowFade: CGFloat = 0.7
        static let badgeHighlight: CGFloat = 0.5
        static let badgeShadowRadius: CGFloat = 1
        static let badgeShadowY: CGFloat = 1
    }

    /// The Settings card's section rail and pane header.
    enum SettingsRail {
        static let rowHeight: CGFloat = 32
        static let rowRadius: CGFloat = 10
        static let rowPadding: CGFloat = 10
        static let iconColumn: CGFloat = 16
        static let headerHeight: CGFloat = 52
        static let panePadding: CGFloat = 28
        /// Space above a group's title, and between its rows.
        static let groupTop: CGFloat = 16
        static let rowVertical: CGFloat = 8
        /// Rows sit flush with the group's title: no card around them to inset from.
        static let rowInset: CGFloat = 0
    }
}

extension Typography {
    static let sidebarRow = Font.system(size: 14)
    static let sidebarRowSelected = Font.system(size: 14, weight: .medium)
    /// The section icons, drawn to sit in an 18 pt column like the design's line icons.
    static let sidebarIcon = Font.system(size: 15)
    /// "Admin", "Settings" above the rail, and the History count.
    static let sidebarLabel = Font.system(size: 12.5, weight: .medium)
    static let sidebarCount = Font.system(size: 12.5).monospacedDigit()
    /// The stat's name beside its badge.
    static let statLabel = Font.system(size: 12.5, weight: .medium)
    static let statCaption = Font.system(size: 12).monospacedDigit()
    static let statGlyph = Font.system(size: 11.5, weight: .semibold)
    /// "Recent" on Home, and a Settings group's title: small, semibold, not shouted.
    static let groupTitle = Font.system(size: 13, weight: .semibold)
    static let link = Font.system(size: 13, weight: .medium)
    /// A Settings pane's title in its header.
    static let paneTitle = Font.system(size: 18, weight: .semibold)
    static let settingsRowTitle = Font.system(size: 14)
    static let settingsRowDetail = Font.system(size: 12.5)
}
