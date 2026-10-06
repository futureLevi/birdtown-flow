import CoreGraphics
import SwiftUI

/// The logo's spectrum disc as a live indicator. It means "your voice is live" and nothing
/// else: the pill's record light, the Dictate button and menu bar status while recording, and
/// the onboarding hero. As a spinning ring it means "working on what you said".
///
/// The disc is painted once per pixel size by `LogoPainter`, the code that draws the app icon,
/// so the orb is the logo's disc rather than an imitation of it. After that it is only turned
/// and masked, which costs next to nothing per frame.
struct SpectrumOrb: View {
    enum Mode: Equatable, Sendable {
        /// Not moving. For static places: About, illustrations.
        case still
        /// Listening: turns slowly and swells a little with the voice.
        case live
        /// Transcribing or polishing: hollows into a ring that spins, head first.
        case thinking
    }

    var mode: Mode = .live
    var diameter: CGFloat
    /// Voice level, 0...1. Swells the orb and brightens its glow while live.
    var level: Float = 0
    /// A soft glow of the orb's own colours. Made for dark surfaces such as the pill; leave it
    /// off on porcelain, where it reads as a smudge.
    var showsHalo = false
    /// Seconds into the animation to draw instead of animating, for snapshots. The frame is
    /// the settled look of `mode` at that moment.
    var phase: Double?
    /// Snapshots pin this; otherwise the system setting applies.
    var reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var dynamics = OrbDynamics()

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        Group {
            if let phase {
                orb(OrbDynamics.settled(mode: mode, level: level, at: phase, reduceMotion: reduceMotion))
            } else if mode == .still || reduceMotion {
                orb(OrbDynamics.settled(mode: mode, level: level, at: 0, reduceMotion: reduceMotion))
            } else {
                TimelineView(.animation) { context in
                    orb(dynamics.step(mode: mode, level: level, at: context.date.timeIntervalSinceReferenceDate))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func orb(_ look: OrbDynamics.Look) -> some View {
        let disc = SpectrumDisc(diameter: diameter, scale: displayScale)
            .mask {
                // The comet tail: faint behind, full at the head, which leads clockwise.
                OrbAperture(hole: look.hole).fill(
                    AngularGradient(colors: [.white.opacity(1 - 0.85 * look.tail), .white], center: .center),
                    style: FillStyle(eoFill: true)
                )
            }
            .rotationEffect(.radians(look.angle))

        return ZStack {
            if showsHalo {
                // Added light, not paint: on the pill's navy the glow brightens what's behind
                // it, so it blooms instead of reading as a dark rim.
                disc
                    .blur(radius: diameter * 0.45)
                    .scaleEffect(1.45)
                    .opacity(look.glow)
                    .blendMode(.plusLighter)
            }
            disc
        }
        .scaleEffect(look.swell)
    }
}

// MARK: - Motion

/// The orb's continuous motion: spin speed, the ring opening and closing, and the voice level
/// all ease toward their targets frame by frame, so switching modes never jumps. A plain class
/// held in `@State`, like `BarSprings`: mutating it never invalidates the view.
final class OrbDynamics {
    struct Look {
        /// Rotation in radians, clockwise.
        var angle: Double
        /// The ring's hole as a fraction of the radius; 0 is the whole disc.
        var hole: CGFloat
        /// 0 is an even ring or disc, 1 a comet with a faint tail.
        var tail: Double
        var swell: CGFloat
        var glow: Double
    }

    private struct Target {
        var speed: Double
        var hole: CGFloat
        var tail: Double
    }

    private var angle: Double = 0
    private var speed: Double?
    private var hole: CGFloat = 0
    private var tail: Double = 0
    private var level: Double = 0
    private var lastTime: Double?

    private static func goal(for mode: SpectrumOrb.Mode) -> Target {
        switch mode {
        case .still: Target(speed: 0, hole: 0, tail: 0)
        case .live: Target(speed: 2 * .pi / Motion.orbTurn, hole: 0, tail: 0)
        case .thinking: Target(speed: 2 * .pi / Motion.orbThinkingTurn, hole: Layout.Orb.ringHole, tail: 1)
        }
    }

    /// The settled look of `mode` at a fixed time: snapshots, Reduce Motion, still orbs.
    static func settled(mode: SpectrumOrb.Mode, level: Float, at time: Double, reduceMotion: Bool) -> Look {
        let aim = Self.goal(for: mode)
        let voice = Double(min(1, max(0, level)))
        return look(
            mode: mode, angle: reduceMotion ? 0 : aim.speed * time, hole: aim.hole,
            tail: aim.tail, level: voice, reduceMotion: reduceMotion)
    }

    func step(mode: SpectrumOrb.Mode, level newLevel: Float, at time: Double) -> Look {
        let aim = Self.goal(for: mode)
        let voice = Double(min(1, max(0, newLevel)))
        defer { lastTime = time }
        guard let last = lastTime, let current = speed else {
            speed = aim.speed
            hole = aim.hole
            tail = aim.tail
            level = voice
            return Self.look(mode: mode, angle: angle, hole: hole, tail: tail, level: level, reduceMotion: false)
        }
        // Clamp so a stall (or a window that was hidden) can't fling the orb round.
        let dt = min(max(time - last, 0), 1.0 / 15.0)
        func ease(_ tau: Double) -> Double { 1 - exp(-dt / tau) }
        let newSpeed = current + (aim.speed - current) * ease(0.35)
        speed = newSpeed
        angle = (angle + newSpeed * dt).truncatingRemainder(dividingBy: 2 * .pi)
        hole += (aim.hole - hole) * CGFloat(ease(0.12))
        tail += (aim.tail - tail) * ease(0.18)
        // Fast attack, slower release, like a VU meter: the orb jumps with a syllable and
        // settles between words.
        level += (voice - level) * ease(voice > level ? 0.05 : 0.22)
        return Self.look(mode: mode, angle: angle, hole: hole, tail: tail, level: level, reduceMotion: false)
    }

    private static func look(
        mode: SpectrumOrb.Mode, angle: Double, hole: CGFloat, tail: Double, level: Double, reduceMotion: Bool
    ) -> Look {
        let live = mode == .live
        // The glow follows the voice even under Reduce Motion (it brightens, it doesn't move).
        let glow = live ? 0.35 + 0.65 * min(1, level * 1.6) : mode == .thinking ? 0.3 : 0.45
        let swell = live && !reduceMotion ? 1 + 0.1 * CGFloat(min(1, level * 1.4)) : 1
        return Look(angle: angle, hole: hole, tail: tail, swell: swell, glow: glow)
    }
}

// MARK: - Drawing

/// A disc with an optional concentric hole, drawn even-odd. The hole animates.
struct OrbAperture: Shape {
    /// Radius of the hole as a fraction of the disc's radius: 0 is the whole disc.
    var hole: CGFloat

    var animatableData: CGFloat {
        get { hole }
        set { hole = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let square = CGRect(
            x: rect.midX - min(rect.width, rect.height) / 2, y: rect.midY - min(rect.width, rect.height) / 2,
            width: min(rect.width, rect.height), height: min(rect.width, rect.height))
        var path = Path(ellipseIn: square)
        if hole > 0.001 {
            let inset = square.width / 2 * (1 - min(hole, 0.98))
            path.addEllipse(in: square.insetBy(dx: inset, dy: inset))
        }
        return path
    }
}

/// The logo's disc as an image, painted once per pixel size.
struct SpectrumDisc: View {
    let diameter: CGFloat
    let scale: CGFloat

    var body: some View {
        if let image = SpectrumDiscCache.image(pixels: SpectrumDiscCache.pixels(diameter: diameter, scale: scale)) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: diameter, height: diameter)
        } else {
            Circle().fill(Spectrum.angular())
                .frame(width: diameter, height: diameter)
        }
    }
}

@MainActor
enum SpectrumDiscCache {
    private static var images: [Int: CGImage] = [:]

    /// Painted at twice the device size: the orb swells and turns, and downsampling keeps its
    /// edge clean at every angle.
    static func pixels(diameter: CGFloat, scale: CGFloat) -> Int {
        max(16, Int((diameter * max(scale, 1) * 2).rounded(.up)))
    }

    static func image(pixels: Int) -> CGImage? {
        if let cached = images[pixels] { return cached }
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let cg = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let side = CGFloat(pixels)
        cg.interpolationQuality = .high
        cg.setShouldAntialias(true)
        // LogoPainter draws y-down; bitmap contexts are y-up.
        cg.translateBy(x: 0, y: side)
        cg.scaleBy(x: 1, y: -1)
        LogoPainter.drawDisc(in: cg, centre: CGPoint(x: side / 2, y: side / 2), radius: side / 2)
        let image = cg.makeImage()
        if images.count > 24 { images.removeAll() }
        images[pixels] = image
        return image
    }
}
