import SwiftUI

/// Bar heights and opacities for one frame of the waveform. Pure function of state and
/// time, so snapshots can freeze any moment and the live view stays allocation-light.
enum HUDWave {
    struct Frame {
        var heights: [CGFloat]
        var opacities: [Double]
    }

    static func frame(kind: HUDState.Kind, levels: [Float], at time: Double, reduceMotion: Bool) -> Frame {
        let count = Layout.HUD.barCount
        let minHeight = Layout.HUD.barMinHeight
        let range = Layout.HUD.barMaxHeight - minHeight
        let rest = Palette.HUD.barRestOpacity
        let peak = Palette.HUD.barPeakOpacity
        var heights = [CGFloat](repeating: minHeight, count: count)
        var opacities = [Double](repeating: rest, count: count)
        let centre = Double(count - 1) / 2

        switch kind {
        case .listening, .handsFree:
            for index in 0..<count {
                let distance = abs(Double(index) - centre)
                // The newest sample sits in the centre and older ones ripple outward, so the
                // voice appears to emanate from the middle rather than scroll past.
                let voice = shape(sample(levels, age: Int(distance.rounded()) * 2))
                // Gentle bell: the centre carries the voice, the edges echo it.
                let bell = 0.36 + 0.64 * exp(-(distance * distance) / 11.5)
                let seed = Double(index) * 1.618
                let wobble = reduceMotion ? 1 : 0.84 + 0.16 * sin(time * (4.3 + 0.41 * Double(index % 5)) + seed)
                // Silence still breathes: a slow ripple across resting bars says "listening".
                let ripple = reduceMotion ? 0 : (0.5 + 0.5 * sin(time * 2.4 - distance * 0.75)) * (1 - voice)
                heights[index] = minHeight + Layout.HUD.idleShimmer * CGFloat(ripple)
                    + range * CGFloat(voice * bell * wobble)
                opacities[index] = rest + (peak - rest) * min(1, voice * 1.7 + ripple * 0.12)
            }
        case .transcribing, .polishing:
            for index in 0..<count {
                let position = Double(index) / Double(count - 1)
                let crest: Double
                if reduceMotion {
                    crest = 0.35 + 0.15 * sin(time * 1.4)
                } else {
                    // A soft crest travelling left to right: thinking, not loading.
                    let wave = 0.5 + 0.5 * sin(2 * .pi * (time * Motion.thinkingFrequency - position * 0.85))
                    crest = wave * wave
                }
                heights[index] = minHeight + 1.5 + CGFloat(crest) * 7.5
                opacities[index] = 0.3 + 0.62 * crest
            }
        default:
            break
        }
        return Frame(heights: heights, opacities: opacities)
    }

    private static func sample(_ levels: [Float], age: Int) -> Double {
        guard !levels.isEmpty else { return 0 }
        let index = max(0, levels.count - 1 - age)
        return Double(min(1, max(0, levels[index])))
    }

    /// Gate the noise floor, then lift quiet speech so ordinary talking uses most of the range.
    private static func shape(_ level: Double) -> Double {
        let gated = max(0, level - 0.02) / 0.98
        return min(1, pow(gated, 0.65) * 1.08)
    }
}

/// Per-bar springs that smooth the waveform between level updates (~30 Hz in, display rate
/// out). A plain class held in `@State`: mutating it never invalidates the view.
final class BarSprings {
    private var position: [CGFloat] = []
    private var velocity: [CGFloat] = []
    private var lastTime: Double?

    func step(toward target: [CGFloat], at time: Double, critical: Bool) -> [CGFloat] {
        guard position.count == target.count, let last = lastTime else {
            position = target
            velocity = Array(repeating: 0, count: target.count)
            lastTime = time
            return target
        }
        // Clamp so a stall (or a paused timeline) can't fling the bars.
        let elapsed = min(max(time - last, 0), 1.0 / 15.0)
        lastTime = time
        guard elapsed > 0 else { return position }

        let stiffness = Motion.barStiffness
        // Reduce Motion: critically damped, so bars follow the voice without overshoot.
        let damping = critical ? 2 * stiffness.squareRoot() : Motion.barDamping
        let steps = max(1, Int((elapsed * 240).rounded(.up)))
        let dt = elapsed / Double(steps)
        for _ in 0..<steps {
            for index in position.indices {
                let x = Double(position[index])
                let v = Double(velocity[index])
                let acceleration = stiffness * (Double(target[index]) - x) - damping * v
                let newVelocity = v + acceleration * dt
                velocity[index] = CGFloat(newVelocity)
                position[index] = CGFloat(x + newVelocity * dt)
            }
        }
        return position
    }
}

/// The bars themselves: one `Canvas`, no per-bar views.
struct HUDBars: View {
    let heights: [CGFloat]
    let opacities: [Double]

    var body: some View {
        let heights = self.heights
        let opacities = self.opacities
        Canvas { context, size in
            let width = Layout.HUD.barWidth
            let step = width + Layout.HUD.barSpacing
            for index in heights.indices {
                let height = min(max(heights[index], width), size.height)
                let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2, width: width, height: height)
                let opacity = index < opacities.count ? opacities[index] : Palette.HUD.barRestOpacity
                context.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(Palette.HUD.barColor.opacity(opacity))
                )
            }
        }
        .frame(width: HUDMetrics.barsWidth, height: Layout.HUD.barMaxHeight + Layout.HUD.idleShimmer * 2)
        .accessibilityHidden(true)
    }
}

/// Ember record dot with a soft breathing pulse and a halo that brightens with the voice.
struct HUDRecordDot: View {
    let breath: Double
    let level: Float
    let reduceMotion: Bool

    var body: some View {
        let diameter = Layout.HUD.recordDot
        let glow = min(1, 0.25 + Double(level) * 1.4) * (0.7 + 0.3 * breath)
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Palette.HUD.emberGlow, Palette.HUD.emberGlow.opacity(0)],
                    center: .center, startRadius: 0, endRadius: diameter * 1.5
                ))
                .frame(width: diameter * 3, height: diameter * 3)
                .opacity(glow)
            Circle()
                .fill(Palette.HUD.ember)
                .frame(width: diameter, height: diameter)
                .scaleEffect(reduceMotion ? 1 : 0.88 + 0.12 * breath)
                .opacity(0.82 + 0.18 * breath)
        }
        .accessibilityHidden(true)
    }
}

/// Polishing: a small sparkle that twinkles in the record dot's place.
struct HUDSparkle: View {
    let breath: Double
    let reduceMotion: Bool

    var body: some View {
        Image(systemName: "sparkle")
            .font(Typography.hudGlyph)
            .foregroundStyle(Palette.HUD.ink)
            .scaleEffect(reduceMotion ? 1 : 0.84 + 0.16 * breath)
            .opacity(0.7 + 0.3 * breath)
            .accessibilityHidden(true)
    }
}

/// Listening, hands-free, transcribing and polishing share one view so the bars keep their
/// identity (and their springs) across those phases and simply change what they do.
struct HUDLiveContent: View {
    let state: HUDState
    let size: CGSize
    let frozenTime: Double?
    let actions: HUDActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var springs = BarSprings()

    var body: some View {
        if let frozenTime {
            liveFrame(at: frozenTime, smooth: false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                liveFrame(at: context.date.timeIntervalSinceReferenceDate, smooth: true)
            }
        }
    }

    private func liveFrame(at time: Double, smooth: Bool) -> some View {
        let wave = HUDWave.frame(kind: state.kind, levels: state.levels, at: time, reduceMotion: reduceMotion)
        let heights = smooth ? springs.step(toward: wave.heights, at: time, critical: reduceMotion) : wave.heights
        let breath = reduceMotion ? 1 : 0.5 + 0.5 * sin(2 * .pi * time / Motion.breathPeriod)
        let midY = size.height / 2
        let handsFree = state.kind == .handsFree
        let layout = HUDMetrics.handsFreeLayout(width: size.width)
        let barsX = handsFree ? layout.bars : size.width / 2

        return ZStack {
            accessory(breath: breath)
                .position(x: HUDMetrics.capCentre, y: midY)

            HUDBars(heights: heights, opacities: wave.opacities)
                .position(x: barsX, y: midY)

            if handsFree {
                Text(HUDMetrics.elapsedText(since: state.recordingStartedAt, now: Date(timeIntervalSinceReferenceDate: time)))
                    .font(Typography.hudNumeral)
                    .foregroundStyle(Palette.HUD.inkSecondary)
                    .lineLimit(1)
                    .frame(width: Layout.HUD.timerWidth, alignment: .trailing)
                    .position(x: layout.timer, y: midY)
                    .transition(.opacity)
                    .accessibilityLabel("Recording time")

                HUDStopButton(isHovered: state.hover == .stop, breath: breath, action: actions.stop)
                    .position(x: layout.stop, y: midY)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func accessory(breath: Double) -> some View {
        ZStack {
            switch state.kind {
            case .listening:
                HUDRecordDot(breath: breath, level: state.level, reduceMotion: reduceMotion)
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
            case .handsFree:
                HUDIconButton(symbol: "xmark", label: "Cancel dictation", isHovered: state.hover == .cancel,
                              action: actions.cancel)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            case .polishing:
                HUDSparkle(breath: breath, reduceMotion: reduceMotion)
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
            default:
                EmptyView()
            }
        }
    }
}
