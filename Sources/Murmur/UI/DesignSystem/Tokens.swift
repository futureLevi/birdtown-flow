import AppKit
import SwiftUI

// MARK: - Murmur design language
//
// "Quiet ink." Murmur sits beside everything you do, so the app recedes: warm paper,
// near-black ink, generous space, and exactly one living colour — Ember — which means
// "listening" or "the thing to press". Serif display type (New York) for anything that is
// *your words* or a page title; SF Pro for interface. Motion is springy but brief, and
// collapses to fades under Reduce Motion.
//
// Rules:
//  - Views never contain literal colours, sizes, radii or durations. Use these tokens; if a
//    token is missing, add it here.
//  - Ember is reserved for recording state and primary actions. Never decorative.
//  - No gradients except the HUD's live waveform glow. No drop shadows heavier than `Elevation`.
//  - Every animation goes through `Motion` so Reduce Motion is honoured everywhere.

enum Palette {
    /// Window background. Warm paper / deep graphite.
    static let canvas = Color.adaptive(light: 0xF7F6F3, dark: 0x1A1A19)
    /// Raised surfaces: cards, rows, popovers.
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x242423)
    /// Hovered surface.
    static let surfaceHover = Color.adaptive(light: 0xF2F1ED, dark: 0x2C2C2A)
    /// Inset wells: text inputs, code, empty states.
    static let sunken = Color.adaptive(light: 0xEFEEEA, dark: 0x141413)
    /// 1px separators and card borders.
    static let hairline = Color.adaptive(light: 0x1C1B19, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.08)
    /// Stronger border for focused inputs and selected cards.
    static let hairlineStrong = Color.adaptive(light: 0x1C1B19, lightAlpha: 0.18, dark: 0xFFFFFF, darkAlpha: 0.18)

    /// Primary text.
    static let ink = Color.adaptive(light: 0x1C1B19, dark: 0xF2F1EE)
    /// Secondary text: metadata, descriptions.
    static let inkSecondary = Color.adaptive(light: 0x6B6862, dark: 0xA3A09A)
    /// Tertiary text: placeholders, disabled, timestamps.
    static let inkTertiary = Color.adaptive(light: 0x9C9891, dark: 0x6F6C67)

    /// The one accent. Recording, primary buttons, selection.
    static let ember = Color.adaptive(light: 0xE5532A, dark: 0xFF6A3D)
    /// Ember at low strength, for selected backgrounds and badges.
    static let emberSoft = Color.adaptive(light: 0xE5532A, lightAlpha: 0.10, dark: 0xFF6A3D, darkAlpha: 0.16)
    /// Text drawn on an Ember fill.
    static let onEmber = Color.white

    static let success = Color.adaptive(light: 0x2F8F57, dark: 0x58C487)
    static let successSoft = Color.adaptive(light: 0x2F8F57, lightAlpha: 0.10, dark: 0x58C487, darkAlpha: 0.16)
    static let warning = Color.adaptive(light: 0xB7791F, dark: 0xF0B04A)
    static let warningSoft = Color.adaptive(light: 0xB7791F, lightAlpha: 0.10, dark: 0xF0B04A, darkAlpha: 0.15)
    static let danger = Color.adaptive(light: 0xC8382B, dark: 0xFF6B5E)
    static let dangerSoft = Color.adaptive(light: 0xC8382B, lightAlpha: 0.09, dark: 0xFF6B5E, darkAlpha: 0.15)

    /// The HUD is always dark, whatever the appearance — it floats over arbitrary content.
    enum HUD {
        static let fill = Color(hex: 0x0F0F0E, alpha: 0.94)
        static let stroke = Color.white.opacity(0.12)
        static let ink = Color.white.opacity(0.94)
        static let inkSecondary = Color.white.opacity(0.56)
        static let bar = Color.white.opacity(0.92)
        static let barIdle = Color.white.opacity(0.30)
        static let ember = Color(hex: 0xFF6A3D)
        static let success = Color(hex: 0x58C487)
        static let danger = Color(hex: 0xFF6B5E)
    }
}

enum Typography {
    /// Page titles: "History", "Good evening, Levi".
    static let display = Font.system(size: 28, weight: .semibold, design: .serif)
    /// Section titles inside a page, sheet titles.
    static let title = Font.system(size: 19, weight: .semibold, design: .serif)
    /// Big numbers in stat tiles.
    static let numeral = Font.system(size: 30, weight: .medium, design: .serif).monospacedDigit()
    /// Card and row headings.
    static let headline = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    /// Dictated text — the user's own words — set in serif so it reads as writing, not UI.
    static let transcript = Font.system(size: 15, design: .serif)
    static let transcriptLarge = Font.system(size: 17, design: .serif)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11, weight: .medium)
    /// Small uppercase labels above sections. Use with `.textCase(.uppercase)` and `Tracking.eyebrow`.
    static let eyebrow = Font.system(size: 10.5, weight: .semibold)
    /// Keycaps and shortcuts.
    static let keycap = Font.system(size: 12, weight: .medium, design: .rounded)
    static let mono = Font.system(size: 12, design: .monospaced)
    /// HUD labels.
    static let hud = Font.system(size: 12, weight: .medium)
    static let hudNumeral = Font.system(size: 12, weight: .medium).monospacedDigit()
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
    /// Waveform bars are drawn in white; opacity carries loudness.
    static let barColor = Color.white
    static let barRestOpacity: Double = 0.42
    static let barPeakOpacity: Double = 0.95
    /// The resting idle pill is a whisper until hovered.
    static let idleOpacity: Double = 0.4
    /// Round HUD buttons at rest and under the pointer.
    static let control = Color.white.opacity(0.08)
    static let controlHover = Color.white.opacity(0.18)
    /// Soft halo behind the record dot; brightens with the voice.
    static let emberGlow = Color(hex: 0xFF6A3D, alpha: 0.55)
    static let dangerSoft = Color(hex: 0xFF6B5E, alpha: 0.18)
    static let onEmber = Color.white
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
    static let stopGlyph: CGFloat = 8
    static let stopGlyphRadius: CGFloat = 2
    static let timerWidth: CGFloat = 32
    static let checkSize: CGFloat = 14
    static let checkStroke: CGFloat = 2
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
    /// Record dot breathing period, seconds.
    static let breathPeriod: Double = 1.8
    /// Travelling "thinking" wave, cycles per second.
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
