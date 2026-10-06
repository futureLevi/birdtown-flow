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
            // The orb's spinning ring says "thinking", so the bars step back: a low dome that
            // breathes slowly instead of a second moving thing competing with the ring.
            let breath = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(2 * .pi * time * Motion.thinkingFrequency)
            for index in 0..<count {
                let edge = abs(Double(index) - centre) / centre
                let dome = 1 - 0.55 * edge * edge
                heights[index] = minHeight + Layout.HUD.thinkingLift * CGFloat(dome)
                opacities[index] = (0.26 + 0.18 * breath) * (0.7 + 0.3 * dome)
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
                    with: .color(Palette.HUD.bar.opacity(opacity))
                )
            }
        }
        .frame(width: HUDMetrics.barsWidth, height: Layout.HUD.barMaxHeight + Layout.HUD.idleShimmer * 2)
        .accessibilityHidden(true)
    }
}

/// The logo's spectrum disc as the pill's live light. One instance lives across listening,
/// hands-free, transcribing and polishing, so it morphs rather than pops: it turns with the
/// voice, hollows into the spinning comet ring when the key is released, and in hands-free it
/// slides to the right end and becomes Stop, a warm-white square on the disc like the logo's
/// white shapes.
struct HUDOrb: View {
    let mode: SpectrumOrb.Mode
    let level: Float
    let isStop: Bool
    let isHovered: Bool
    let phase: Double?
    let reduceMotion: Bool
    let stop: @MainActor () -> Void

    var body: some View {
        // Painted once at the Stop size and scaled down as the record light, so moving between
        // the two is a smooth scale rather than a repaint.
        let side = Layout.HUD.stopOrb
        let scale = isStop ? (isHovered ? Layout.HUD.stopHoverScale : 1) : Layout.HUD.orb / side
        let label: String = isStop ? "Stop and insert" : "Listening"
        Button {
            if isStop { stop() }
        } label: {
            ZStack {
                SpectrumOrb(mode: mode, diameter: side, level: level, showsHalo: !isStop, phase: phase,
                            reduceMotionOverride: reduceMotion)
                RoundedRectangle(cornerRadius: Layout.HUD.stopGlyphRadius, style: .continuous)
                    .fill(Palette.HUD.bar)
                    .frame(width: Layout.HUD.stopGlyph, height: Layout.HUD.stopGlyph)
                    .opacity(isStop ? 1 : 0)
            }
            .frame(width: side, height: side)
            .scaleEffect(scale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isStop)
        .accessibilityLabel(label)
        .accessibilityHidden(!isStop)
        .help(label)
    }
}

/// Listening, hands-free, transcribing and polishing share one view so the bars keep their
/// identity (and their springs) across those phases and simply change what they do.
struct HUDLiveContent: View {
    let state: HUDState
    let size: CGSize
    let frozenTime: Double?
    let reduceMotion: Bool
    let actions: HUDActions

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
        let thinking = state.kind == .transcribing || state.kind == .polishing
        let midY = size.height / 2
        let handsFree = state.kind == .handsFree
        let layout = HUDMetrics.handsFreeLayout(width: size.width)
        let barsX = handsFree ? layout.bars : size.width / 2

        return ZStack {
            accessory
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

            }

            // The one orb, outside any per-state branch so it keeps its identity (and its
            // motion) from listening through thinking.
            HUDOrb(mode: thinking ? .thinking : .live, level: state.level, isStop: handsFree,
                   isHovered: state.hover == .stop, phase: frozenTime, reduceMotion: reduceMotion,
                   stop: actions.stop)
                .position(x: handsFree ? layout.stop : HUDMetrics.capCentre, y: midY)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Hands-free puts Cancel in the left cap the orb leaves for the Stop end.
    private var accessory: some View {
        ZStack {
            if state.kind == .handsFree {
                HUDIconButton(symbol: "xmark", label: "Cancel dictation", isHovered: state.hover == .cancel,
                              action: actions.cancel)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
    }
}
