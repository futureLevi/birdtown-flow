import SwiftUI

/// One complete dictation, frame by frame, for the README animation: the resting pill, a
/// press, a phrase of speech, release into the thinking wave, the check, and back to rest.
///
/// Every frame is a pure function of its index. Pill geometry follows `Motion.pill`'s spring
/// analytically, and the bars are run through the same per-bar springs as the live HUD on
/// synthetic 30 Hz levels, simulated once up front, so the sequence renders identically on
/// every run (no wall-clock `TimelineView`).
@MainActor
enum HUDFilm {
    static let fps: Double = 30
    static let size = CGSize(width: 600, height: 200)

    // The script, in seconds.
    static let pressAt = 0.4
    static let releaseAt = 2.0
    static let doneAt = 2.8
    static let idleAt = 3.6
    static let end = 4.2

    static var frameCount: Int { Int((end * fps).rounded()) }

    struct Frame {
        var time: Double
        var heights: [CGFloat]
        var opacities: [Double]
        var level: Float
        /// The orb, stepped by the same dynamics as the live `SpectrumOrb`, so the morph into
        /// the thinking ring plays out across frames instead of cutting.
        var orb: OrbDynamics.Look
    }

    static let frames: [Frame] = simulate()

    static func kind(at time: Double) -> HUDState.Kind {
        if time < pressAt { return .idle }
        if time < releaseAt { return .listening }
        if time < doneAt { return .transcribing }
        if time < idleAt { return .done }
        return .idle
    }

    /// Syllables (about five a second) under a slower phrase envelope, like the recorder's
    /// level stream for a short sentence.
    static func speechLevel(at time: Double) -> Float {
        let start = pressAt + 0.12
        guard time >= start, time < releaseAt - 0.06 else { return 0.008 }
        let s = time - start
        let syllable = pow(abs(sin(.pi * 4.6 * s)), 0.8)
        let phrase = 0.55 + 0.45 * sin(2 * .pi * 0.9 * s + 0.6)
        let accent = 0.85 + 0.15 * sin(2 * .pi * 2.3 * s + 1.7)
        let fadeIn = min(1, s / 0.12)
        return Float(min(1, 0.62 * syllable * phrase * accent * fadeIn + 0.01))
    }

    private static func simulate() -> [Frame] {
        let springs = BarSprings()
        let orbDynamics = OrbDynamics()
        var orb = OrbDynamics.settled(mode: .live, level: 0, at: 0, reduceMotion: false)
        let tick = 1.0 / 120.0
        var history = [Float](repeating: 0, count: DictationController.levelHistoryCount)
        var level: Float = 0
        var nextSample = 0.0
        var time = 0.0
        var heights: [CGFloat] = []
        var opacities: [Double] = []
        var frames: [Frame] = []
        for index in 0..<frameCount {
            let frameTime = Double(index) / fps
            while time <= frameTime + 1e-9 {
                if time >= nextSample {
                    // The controller's smoothing: fast attack, slower release.
                    let value = speechLevel(at: time)
                    level = value >= level ? value * 0.7 + level * 0.3 : value * 0.25 + level * 0.75
                    history.removeFirst()
                    history.append(value)
                    nextSample += 1.0 / 30.0
                }
                let wave = HUDWave.frame(kind: kind(at: time), levels: history, at: time, reduceMotion: false)
                heights = springs.step(toward: wave.heights, at: time, critical: false)
                let thinking = time >= releaseAt
                orb = orbDynamics.step(mode: thinking ? .thinking : .live, level: thinking ? 0 : level, at: time)
                opacities = wave.opacities
                time += tick
            }
            frames.append(Frame(time: frameTime, heights: heights, opacities: opacities, level: level, orb: orb))
        }
        return frames
    }

    // MARK: - Curves

    /// Step response of `Motion.pill`: 0 → 1 with its small overshoot.
    static func pillSpring(_ elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let omega = 2 * .pi / Motion.pillResponse
        let zeta = Motion.pillDamping
        let damped = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * elapsed)
        return 1 - decay * (cos(damped * elapsed) + zeta * omega / damped * sin(damped * elapsed))
    }

    /// Ease-out progress of a fade that starts at `start` and lasts `duration`.
    static func fade(_ time: Double, from start: Double, over duration: Double) -> Double {
        let x = min(max((time - start) / duration, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    struct Pill {
        var size: CGSize
        var opacity: Double
        /// 1 while resting, 0 once awake; drives the resting edge and shadow.
        var rest: Double
    }

    static func pill(at time: Double) -> Pill {
        let idle = Layout.HUD.idleSize
        let live = CGSize(width: Layout.HUD.listeningWidth, height: Layout.HUD.height)
        let done = CGSize(width: Layout.HUD.height, height: Layout.HUD.height)
        func mix(_ a: CGSize, _ b: CGSize, _ p: Double) -> CGSize {
            let t = CGFloat(p)
            return CGSize(width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
        }
        let idleOpacity = Palette.HUD.idleOpacity
        if time < pressAt {
            return Pill(size: idle, opacity: idleOpacity, rest: 1)
        } else if time < doneAt {
            let p = pillSpring(time - pressAt)
            let awake = min(max(p, 0), 1)
            return Pill(size: mix(idle, live, p), opacity: idleOpacity + (1 - idleOpacity) * awake, rest: 1 - awake)
        } else if time < idleAt {
            return Pill(size: mix(live, done, pillSpring(time - doneAt)), opacity: 1, rest: 0)
        } else {
            let p = pillSpring(time - idleAt)
            let asleep = min(max(p, 0), 1)
            return Pill(size: mix(done, idle, p), opacity: 1 - (1 - idleOpacity) * asleep, rest: asleep)
        }
    }
}

/// One frame of the film, over the dark editor backdrop.
struct HUDFilmFrame: View {
    let index: Int

    var body: some View {
        let frame = HUDFilm.frames[min(index, HUDFilm.frames.count - 1)]
        let time = frame.time
        let pill = HUDFilm.pill(at: time)
        let live = HUDFilm.fade(time, from: HUDFilm.pressAt + 0.04, over: 0.2)
            * (1 - HUDFilm.fade(time, from: HUDFilm.doneAt, over: 0.14))
        let check = HUDFilm.fade(time, from: HUDFilm.doneAt + 0.04, over: 0.16)
            * (1 - HUDFilm.fade(time, from: HUDFilm.idleAt, over: 0.12))
        let trim = HUDFilm.fade(time, from: HUDFilm.doneAt + 0.08, over: 0.34)
        let awake = CGFloat(1 - pill.rest)
        let shadowScale = Palette.HUD.idleShadowScale + (1 - Palette.HUD.idleShadowScale) * awake

        ZStack(alignment: .bottom) {
            HUDBackdrop()
            ZStack {
                HUDPillBody(stroke: pill.rest > 0.5 ? Palette.HUD.idleStroke : Palette.HUD.stroke,
                            shadowScale: shadowScale)
                ZStack {
                    ZStack {
                        HUDFilmOrb(look: frame.orb, diameter: Layout.HUD.orb)
                            .position(x: HUDMetrics.capCentre, y: pill.size.height / 2)
                        HUDBars(heights: frame.heights, opacities: frame.opacities)
                            .position(x: pill.size.width / 2, y: pill.size.height / 2)
                    }
                    .opacity(live)
                    .scaleEffect(CGFloat(0.9 + 0.1 * live))

                    HUDDrawnCheck(animated: false, fixedProgress: trim)
                        .opacity(check)
                        .scaleEffect(CGFloat(0.9 + 0.1 * check))
                }
                .frame(width: pill.size.width, height: pill.size.height)
                .clipShape(Capsule(style: .continuous))
            }
            .frame(width: pill.size.width, height: pill.size.height)
            .opacity(pill.opacity)
            .padding(.bottom, HUDBackdrop.dockVisible + Layout.HUD.bottomInset)
        }
        .frame(width: HUDFilm.size.width, height: HUDFilm.size.height)
        .clipped()
    }
}

/// `SpectrumOrb`'s drawing, fed a precomputed look so the film can show the ring opening
/// frame by frame (a snapshot `SpectrumOrb` only draws a mode's settled look).
struct HUDFilmOrb: View {
    let look: OrbDynamics.Look
    let diameter: CGFloat

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let comet = AngularGradient(colors: [.white.opacity(1 - 0.85 * look.tail), .white], center: .center)
        let radius = diameter / 2
        ZStack {
            SpectrumHalo(diameter: diameter, scale: displayScale)
                .mask {
                    RadialGradient(colors: [.clear, .white], center: .center,
                                   startRadius: look.hole * radius * 0.9, endRadius: radius)
                }
                .mask { Circle().fill(comet) }
                .opacity(look.glow)
                .blendMode(.plusLighter)
            SpectrumDisc(diameter: diameter, scale: displayScale)
                .mask { OrbAperture(hole: look.hole).fill(comet, style: FillStyle(eoFill: true)) }
        }
        .rotationEffect(.radians(look.angle))
        .scaleEffect(look.swell)
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
