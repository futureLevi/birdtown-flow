import MurmurKit
import SwiftUI

/// The Voiceprint: a mirrored voice waveform of fine tapered lines in the logo's spectrum,
/// shaped by the pill's 18-bar rhythm. It rises out of the navy in violet under the end of the
/// greeting, burns cyan at its loudest and trails off in warm gold. Drawn in the hero's
/// 660 x 150 pt design space from the approved design's data (`VoiceprintData.swift`).
///
/// It moves only as Shimmer (`VoiceprintMotion`): a soft band of light glides across the
/// still lines every few seconds, after a one-time opening as Home appears. It holds still
/// with Reduce Motion, while the window is in the background and while Home is scrolled
/// away from it.
///
/// Cost: between sweeps nothing redraws (the timeline is paused). During a sweep or the
/// opening, two canvases of about 130 small shapes redraw at up to 60 Hz. The haze and glows
/// are static layers the GPU only composites. The design's soft light (its CSS blurs) is
/// painted as gradients rather than blurred, so it costs nothing per frame and snapshots
/// show what people see.
struct VoiceprintArt: View {
    /// Seconds into a sweep to draw instead of animating, for snapshots.
    var sweepPhase: Double?
    /// Whether any of the hero is on screen. Off-screen, it holds still.
    var isOnScreen = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    /// Set while the timeline should tick: during the opening and during a sweep.
    @State private var isRunning = false
    @State private var hasOpened = false
    @State private var openingStart: Date?
    @State private var sweepStart: Date?

    private var canAnimate: Bool {
        sweepPhase == nil && !reduceMotion && appearsActive && isOnScreen
    }

    /// Before the opening has played, the voice is not there yet.
    private var openingPending: Bool { canAnimate && !hasOpened }

    var body: some View {
        ZStack {
            haze
            glows
            TimelineView(.animation(minimumInterval: Motion.heroFrameInterval, paused: !isRunning)) { context in
                let look = motionFrame(at: context.date)
                ZStack {
                    Canvas { context, _ in Voiceprint.drawBloom(in: &context, frame: look) }
                        .opacity(Voiceprint.Bloom.opacity)
                        .blendMode(.screen)
                    Canvas { context, _ in Voiceprint.drawLines(in: &context, frame: look) }
                }
            }
        }
        .frame(width: Layout.Hero.designWidth, height: Layout.Hero.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: canAnimate) { await run() }
    }

    // MARK: Static layers

    /// A broad spectral haze behind the swell: the design's ellipse with its horizontal
    /// spectrum, softened as its blur would soften it.
    private var haze: some View {
        let haze = Voiceprint.haze
        let rect = haze.rect.insetBy(dx: -Voiceprint.Soft.reach * haze.blur, dy: -Voiceprint.Soft.reach * haze.blur)
        // The spectrum's stops, moved into the wider frame (it runs past its ends in the end
        // colours, as the blur spreads them).
        let colors = haze.stops.map {
            Gradient.Stop(color: Color(hex: $0.color, alpha: $0.alpha),
                          location: (haze.rect.minX - rect.minX + $0.location * haze.rect.width) / rect.width)
        }
        return Rectangle()
            .fill(LinearGradient(stops: colors, startPoint: .leading, endPoint: .trailing))
            .mask {
                LinearGradient(
                    stops: Voiceprint.Soft.blurredBand(halfWidth: haze.rect.width / 2, sigma: haze.blur),
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .mask {
                LinearGradient(
                    stops: Voiceprint.Soft.blurredBand(halfWidth: haze.rect.height / 2, sigma: haze.blur),
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(width: rect.width, height: rect.height)
            .opacity(haze.opacity)
            .position(x: rect.midX, y: rect.midY)
            .blendMode(.screen)
    }

    /// Soft light behind the loudest syllables. They rise with the opening, each as its
    /// syllable does.
    private var glows: some View {
        ZStack {
            ForEach(Array(Voiceprint.glows.enumerated()), id: \.offset) { _, glow in
                let rect = glow.rect.insetBy(dx: -Voiceprint.Soft.reach * Voiceprint.Bloom.glowBlur,
                                             dy: -Voiceprint.Soft.reach * Voiceprint.Bloom.glowBlur)
                Ellipse()
                    .fill(EllipticalGradient(
                        stops: Voiceprint.Soft.blurredGlow(
                            color: Color(hex: glow.color), alpha: glow.alpha,
                            halfWidth: glow.rect.width / 2, sigma: Voiceprint.Bloom.glowBlur
                        ),
                        center: .center,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.5
                    ))
                    .frame(width: rect.width, height: rect.height)
                    .scaleEffect(x: 1, y: openingPending ? 0.01 : 1)
                    .opacity(openingPending ? 0 : 1)
                    .animation(
                        Motion.heroGlowRise.delay(VoiceprintMotion.opening(delayAt: Double(glow.centerX))),
                        value: openingPending
                    )
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.screen)
            }
        }
        .frame(width: Layout.Hero.designWidth, height: Layout.Hero.height)
    }

    // MARK: Motion

    private func motionFrame(at date: Date) -> Voiceprint.Frame {
        if let sweepPhase { return Voiceprint.Frame(sweepTime: sweepPhase) }
        if openingPending { return Voiceprint.Frame(openingTime: 0) }
        guard isRunning else { return Voiceprint.Frame() }
        return Voiceprint.Frame(
            sweepTime: sweepStart.map { date.timeIntervalSince($0) },
            openingTime: openingStart.map { date.timeIntervalSince($0) }
        )
    }

    /// Plays the opening once, then a sweep every `VoiceprintMotion.sweepInterval`, for as long
    /// as the hero may move. Restarted (or stopped) whenever that changes.
    private func run() async {
        isRunning = false
        sweepStart = nil
        openingStart = nil
        guard canAnimate else { return }

        var rest = VoiceprintMotion.restDuration
        if !hasOpened {
            hasOpened = true
            openingStart = .now
            isRunning = true
            try? await Task.sleep(for: .seconds(VoiceprintMotion.openingDuration))
            if Task.isCancelled { return }
            openingStart = nil
            isRunning = false
            rest = Motion.heroFirstSweepDelay
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(rest))
            if Task.isCancelled { return }
            sweepStart = .now
            isRunning = true
            try? await Task.sleep(for: .seconds(VoiceprintMotion.sweepDuration))
            if Task.isCancelled { return }
            isRunning = false
            sweepStart = nil
            rest = VoiceprintMotion.restDuration
        }
    }
}

private extension VoiceprintMotion {
    /// When the opening reaches a line at `x`: the delay before it starts to rise.
    static func opening(delayAt x: Double) -> Double {
        max(0, (x - openingStartX) / openingSpanX * openingStagger)
    }
}

// MARK: - Drawing

/// The Voiceprint's data and drawing, free of any view so the canvases can call it from
/// their render closures.
enum Voiceprint {
    /// One hairline: a thin lens, widest and whitest on the centre line, pointed at both tips.
    struct Line {
        var x: Double
        /// Half-height at rest.
        var amp: Double
        /// 0...1 visibility along the voice: a whisper at the start, easing off at the end.
        var presence: Double
        /// Body brightness of the quietest line (warm hues keep more, so gold doesn't go grey).
        var floor: Double
        var body: UInt32
        /// The whiter lens inside the body, the white-hot sliver inside loud lines, the band's
        /// light, and the blurred glow that follows each loud line.
        var core: UInt32
        var hot: UInt32
        var sheen: UInt32
        var bloom: UInt32
        var bloomAlpha: Double
    }

    struct Haze {
        struct Stop {
            var color: UInt32
            var alpha: Double
            var location: CGFloat
        }

        var rect: CGRect
        var blur: CGFloat
        var opacity: Double
        var stops: [Stop]
    }

    struct Glow {
        var centerX: CGFloat
        var rect: CGRect
        var color: UInt32
        var alpha: Double
    }

    /// What moves in one frame: seconds into the current sweep and into the opening, nil when
    /// neither is running (the lines at rest).
    struct Frame {
        var sweepTime: Double?
        var openingTime: Double?

        func sheen(at x: Double) -> Double {
            sweepTime.map { VoiceprintMotion.sheen(x: x, sweepTime: $0) } ?? 0
        }

        func rise(at x: Double) -> Double {
            openingTime.map { VoiceprintMotion.opening(x: x, at: $0) } ?? 1
        }
    }

    private struct Colors {
        let body: Color
        let core: Color
        let hot: Color
        let sheen: Color
        let bloom: Color
    }

    private static let colors: [Colors] = lines.map {
        Colors(body: Color(hex: $0.body), core: Color(hex: $0.core), hot: Color(hex: $0.hot),
               sheen: Color(hex: $0.sheen), bloom: Color(hex: $0.bloom))
    }

    /// Lines left of this get no bloom: it would sit behind the greeting.
    private static let bloomFromX: Double = 300

    /// 0...1: how loud a line is relative to the loudest syllable.
    private static func loudness(_ amp: Double) -> Double {
        pow(VoiceprintMotion.clamp(amp / (0.72 * Double(maxAmplitude))), 0.8)
    }

    /// A lens's width on the centre line: louder lines are wider.
    private static func bodyWidth(_ loudness: Double) -> Double {
        0.7 + 1.15 * pow(loudness, 0.85)
    }

    static func drawLines(in context: inout GraphicsContext, frame: Frame) {
        for (index, line) in lines.enumerated() {
            let sheen = frame.sheen(at: line.x)
            let rise = frame.rise(at: line.x)
            let amp = line.amp * VoiceprintMotion.heightFactor(sheen: sheen) * rise
            guard amp >= 0.05 else { continue }
            let loud = loudness(amp)
            let width = max(bodyWidth(loud), 0.2)
            let presence = line.presence * (0.35 + 0.65 * rise)
            let color = colors[index]

            fill(&context, x: line.x, halfHeight: max(amp, 0.4), width: width, color: color.body,
                 alpha: 0.95 * presence * (line.floor + (1 - line.floor) * loud) * (1 + 0.25 * sheen))
            if amp * 0.6 >= 0.8 {
                fill(&context, x: line.x, halfHeight: amp * 0.6, width: width * 0.52, color: color.core,
                     alpha: 0.9 * presence * (0.22 + 0.78 * loud))
            }
            let heat = pow(VoiceprintMotion.clamp((loud - 0.4) / 0.6), 1.2)
            if heat > 0 {
                fill(&context, x: line.x, halfHeight: amp * 0.3, width: width * 0.3, color: color.hot,
                     alpha: 0.95 * presence * heat)
            }
            if sheen > 0.01 {
                fill(&context, x: line.x, halfHeight: amp * 0.82, width: width * 0.62, color: color.sheen,
                     alpha: 0.7 * presence * sheen)
            }
        }
        context.opacity = 1
    }

    /// The loud lines again as soft, round-capped strokes: the design's blurred bloom, painted
    /// as a few widening, fainter strokes instead of blurred.
    static func drawBloom(in context: inout GraphicsContext, frame: Frame) {
        let passes = bloomPasses.map {
            (style: StrokeStyle(lineWidth: Bloom.width + $0.spread * Bloom.blur, lineCap: .round), alpha: $0.alpha)
        }
        for (index, line) in lines.enumerated() where line.x > bloomFromX {
            let sheen = frame.sheen(at: line.x)
            let amp = line.amp * VoiceprintMotion.heightFactor(sheen: sheen) * frame.rise(at: line.x)
            let weight = VoiceprintMotion.smoothstep((amp - 5) / 2)
            guard weight > 0 else { continue }
            let half = CGFloat(amp) * Bloom.heightFraction
            var path = Path()
            path.move(to: CGPoint(x: line.x, y: Double(centerY - half)))
            path.addLine(to: CGPoint(x: line.x, y: Double(centerY + half)))
            let strength = VoiceprintMotion.clamp(line.bloomAlpha * weight * (1 + 0.6 * sheen))
            for pass in passes {
                context.opacity = strength * pass.alpha
                context.stroke(path, with: .color(colors[index].bloom), style: pass.style)
            }
        }
        context.opacity = 1
    }

    /// The bloom's blur as strokes: each pass is wider by `spread` blur radii and adds `alpha`
    /// of the light, so the centre gets about a third of a sharp line's, as a blur gives it.
    private struct BloomPass {
        let spread: CGFloat
        let alpha: Double
    }

    private static let bloomPasses = [
        BloomPass(spread: 0, alpha: 0.12),
        BloomPass(spread: 1.2, alpha: 0.12),
        BloomPass(spread: 2.6, alpha: 0.12),
    ]

    /// Painted stand-ins for the design's gaussian blurs (CSS `blur(r)` is a gaussian with
    /// sigma r).
    enum Soft {
        /// How far, in sigmas, painted light reaches past the shape it softens.
        static let reach: CGFloat = 2.5
        private static let samples = 16

        /// A band `2 * halfWidth` wide, blurred, across a span `reach` sigmas wider on each
        /// side: alpha stops for a mask.
        static func blurredBand(halfWidth: CGFloat, sigma: CGFloat) -> [Gradient.Stop] {
            let extent = halfWidth + reach * sigma
            let scale = Double(sigma) * 2.0.squareRoot()
            return (0...samples).map { index in
                let location = Double(index) / Double(samples)
                let x = (location * 2 - 1) * Double(extent)
                let alpha = 0.5 * (erf((x + Double(halfWidth)) / scale) - erf((x - Double(halfWidth)) / scale))
                return Gradient.Stop(color: .white.opacity(alpha), location: location)
            }
        }

        /// A radial glow fading linearly from `alpha` at its centre to nothing at `halfWidth`,
        /// blurred: colour stops from the centre out to `reach` sigmas past its edge.
        static func blurredGlow(color: Color, alpha: Double, halfWidth: CGFloat, sigma: CGFloat) -> [Gradient.Stop] {
            let extent = Double(halfWidth + reach * sigma)
            let half = Double(halfWidth)
            let sigma = Double(sigma)
            let cone = { (x: Double) in max(0, 1 - abs(x) / half) }
            // Sample the blur along one axis; the glow's ellipse carries it around.
            let step = 0.5
            let kernel = stride(from: -3 * sigma, through: 3 * sigma, by: step).map { offset in
                (offset, exp(-offset * offset / (2 * sigma * sigma)))
            }
            let total = kernel.reduce(0) { $0 + $1.1 }
            return (0...samples).map { index in
                let location = Double(index) / Double(samples)
                let x = location * extent
                let value = kernel.reduce(0) { $0 + cone(x - $1.0) * $1.1 } / total
                return Gradient.Stop(color: color.opacity(alpha * value), location: location)
            }
        }
    }

    private static func fill(
        _ context: inout GraphicsContext,
        x: Double, halfHeight: Double, width: Double, color: Color, alpha: Double
    ) {
        let alpha = VoiceprintMotion.clamp(alpha)
        guard alpha > 0.002 else { return }
        context.opacity = alpha
        context.fill(lens(x: x, halfHeight: halfHeight, width: width), with: .color(color))
    }

    /// A vertical lens on the centre line: two quadratic curves meeting in points at the tips.
    private static func lens(x: Double, halfHeight: Double, width: Double) -> Path {
        let y = Double(centerY)
        var path = Path()
        path.move(to: CGPoint(x: x, y: y - halfHeight))
        path.addQuadCurve(to: CGPoint(x: x, y: y + halfHeight), control: CGPoint(x: x + width, y: y))
        path.addQuadCurve(to: CGPoint(x: x, y: y - halfHeight), control: CGPoint(x: x - width, y: y))
        path.closeSubpath()
        return path
    }
}
