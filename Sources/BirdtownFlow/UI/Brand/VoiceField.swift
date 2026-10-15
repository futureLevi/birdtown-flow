import SwiftUI

/// The Home artwork's geometry, from the handoff's `flow-voice-field.svg`: a 650 x 410 box in
/// which a violet-blue-teal surface sits behind five white capsule bars (short, tall, tallest,
/// tall, short: the logo's rhythm). The numbers are art data, not interface values.
enum VoiceFieldGeometry {
    static let size = CGSize(width: 650, height: 410)
    /// The surface and the pigments move about this point, so the middle (and the bars on it)
    /// stays put while the edges drift.
    static let pivot = CGPoint(x: 453, y: 224)

    // The pale disc behind everything, and the halo ring on its edge.
    static let washBounds = CGRect(x: 170, y: -141, width: 534, height: 534)
    static let washOpacity: Double = 0.75
    static let washStart = CGPoint(x: 175, y: 15)
    static let washEnd = CGPoint(x: 592, y: 321)
    static let washMiddle: CGFloat = 0.6
    static let haloWidth: CGFloat = 33
    static let haloOpacity: Double = 0.76

    // The coloured surface: a 580 pt square of layers, clipped to the drifting outline.
    static let layer = CGRect(x: 160, y: -60, width: 580, height: 580)
    static let surfaceStart = CGPoint(x: 271, y: 75)
    static let surfaceEnd = CGPoint(x: 565, y: 354)
    static let surfaceMiddle: CGFloat = 0.58
    static let violetCenter = CGPoint(x: 321.76, y: 204.7)
    static let violetRadius: CGFloat = 289.5
    static let violetAlpha: Double = 0.85
    static let tealCenter = CGPoint(x: 622.84, y: 274.18)
    static let tealRadius: CGFloat = 308.8
    static let tealAlpha: Double = 0.8
    static let warmthCenter = CGPoint(x: 548, y: 38)
    static let warmthRadius: CGFloat = 249.5
    static let warmthAlpha: Double = 0.98
    /// Where the highlight has faded out, as a fraction of its radius.
    static let warmthFade: CGFloat = 0.85

    // The bars, and the square their shared gradient is laid over.
    static let bars: [CGRect] = [
        CGRect(x: 291, y: 177, width: 35, height: 62),
        CGRect(x: 345, y: 145, width: 35, height: 126),
        CGRect(x: 399, y: 122, width: 35, height: 172),
        CGRect(x: 453, y: 145, width: 35, height: 126),
        CGRect(x: 507, y: 177, width: 35, height: 62),
    ]
    static let barsLayer = CGRect(x: 216, y: 40, width: 340, height: 340)
    static let barsStart = CGPoint(x: 290, y: 112)
    static let barsEnd = CGPoint(x: 536, y: 296)
    static let barsMiddle: CGFloat = 0.56

    /// The art fades into the page: out at the top and bottom, and in from the left. The
    /// colours are masks' alpha only.
    static let verticalFade: [Gradient.Stop] = [
        .init(color: .clear, location: 0),
        .init(color: .clear, location: 0.12),
        .init(color: .black, location: 0.38),
        .init(color: .black, location: 0.64),
        .init(color: .clear, location: 1),
    ]
    static let horizontalFade: [Gradient.Stop] = [
        .init(color: .clear, location: 0),
        .init(color: .black, location: 0.2),
        .init(color: .black, location: 1),
    ]

    // MARK: Drift

    /// How far a pigment turns and stretches between the two ends of its cycle (the handoff's
    /// "deformation 50%").
    struct PigmentMotion {
        let rotation: (from: Double, to: Double)
        let scaleX: (from: Double, to: Double)
        let scaleY: (from: Double, to: Double)

        func transform(at blend: Double) -> (rotation: Double, scaleX: CGFloat, scaleY: CGFloat) {
            (
                rotation: rotation.from + (rotation.to - rotation.from) * blend,
                scaleX: CGFloat(scaleX.from + (scaleX.to - scaleX.from) * blend),
                scaleY: CGFloat(scaleY.from + (scaleY.to - scaleY.from) * blend)
            )
        }
    }

    static let violetMotion = PigmentMotion(rotation: (-1, 1), scaleX: (1.015, 0.995), scaleY: (0.995, 1.025))
    static let tealMotion = PigmentMotion(rotation: (0.8, -0.8), scaleX: (0.995, 1.02), scaleY: (1.015, 0.995))

    /// The surface's outline at three moments of the cycle, each a start point and eight cubic
    /// segments (control, control, end): 25 points, as x, y pairs. The first is the resting
    /// shape; the cycle runs 0, 1, 2, back to 0.
    static let surfaces: [[Double]] = [
        [
            654, 224, 654, 277.309, 625.192, 324.829, 587.536, 358.536, 549.881, 392.244,
            503.517, 414.474, 453, 414.474, 402.483, 414.474, 356.119, 392.244, 318.464, 358.536,
            280.808, 324.829, 252, 277.309, 252, 224, 252, 170.691, 280.808, 123.171,
            318.464, 89.464, 356.119, 55.756, 402.483, 33.526, 453, 33.526, 503.517, 33.526,
            549.881, 55.756, 587.536, 89.464, 625.192, 123.171, 654, 170.691, 654, 224,
        ],
        [
            642, 224, 642.097, 274.126, 623.604, 323.411, 587.216, 358.216, 550.829, 393.022,
            504.522, 413.331, 453, 418.263, 401.478, 423.195, 346.879, 404.733, 312.338, 364.662,
            277.797, 324.591, 264.097, 274.126, 264, 224, 263.903, 173.874, 282.396, 124.589,
            318.784, 89.784, 355.171, 54.978, 401.478, 34.669, 453, 29.737, 504.522, 24.805,
            559.121, 43.267, 593.662, 83.338, 628.203, 123.409, 641.903, 173.874, 642, 224,
        ],
        [
            642, 224, 641.903, 274.126, 628.203, 324.591, 593.662, 364.662, 559.121, 404.733,
            504.522, 423.195, 453, 418.263, 401.478, 413.331, 355.171, 393.022, 318.784, 358.216,
            282.396, 323.411, 263.903, 274.126, 264, 224, 264.097, 173.874, 277.797, 123.409,
            312.338, 83.338, 346.879, 43.267, 401.478, 24.805, 453, 29.737, 504.522, 34.669,
            550.829, 54.978, 587.216, 89.784, 623.604, 124.589, 642.097, 173.874, 642, 224,
        ],
    ]

    /// How far through its cycle the drift is `seconds` after the reference date, from 0 up to 1.
    static func progress(atSeconds seconds: Double) -> Double {
        let cycle = Motion.fieldCycle
        let into = seconds.truncatingRemainder(dividingBy: cycle)
        return (into < 0 ? into + cycle : into) / cycle
    }

    /// An ease-in-out between two keyframes.
    static func ease(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    /// The surface outline `progress` of the way round the cycle: the three shapes, blended.
    static func surface(at progress: Double) -> [CGPoint] {
        let position = max(0, progress) * Double(surfaces.count)
        let index = min(Int(position), surfaces.count - 1)
        let blend = ease(position - Double(index))
        let from = surfaces[index]
        let to = surfaces[(index + 1) % surfaces.count]
        return stride(from: 0, to: from.count - 1, by: 2).map { i in
            CGPoint(
                x: from[i] + (to[i] - from[i]) * blend,
                y: from[i + 1] + (to[i + 1] - from[i + 1]) * blend
            )
        }
    }

    /// How far the pigments have moved between their two ends: out and back over the cycle.
    static func pigmentBlend(at progress: Double) -> Double {
        ease(1 - abs(2 * progress - 1))
    }

    /// A point of a layer's rectangle as a gradient's unit point.
    static func unit(_ point: CGPoint, in rect: CGRect) -> UnitPoint {
        UnitPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }
}

/// The coloured surface's outline, redrawn from `VoiceFieldGeometry.surface(at:)`.
private struct VoiceFieldSurface: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // A start point and eight segments of three points each.
        guard points.count == 25 else { return path }
        path.move(to: points[0])
        for segment in 0..<8 {
            let base = 3 * segment
            path.addCurve(to: points[base + 3], control1: points[base + 1], control2: points[base + 2])
        }
        path.closeSubpath()
        return path
    }
}

/// Home's artwork: a cropped violet-blue-teal surface with a small apricot highlight and five
/// white capsule bars, drawn natively from the handoff's voice field. It is flat, with no depth
/// shading, and the surface and pigments drift slowly (a 20 s cycle) around a fixed centre; the
/// bars and the halo stay still. Under Reduce Motion it rests. It's decoration: hidden from
/// accessibility and never hit by the pointer.
///
/// It has no card, border or shadow: the caller places it on the canvas and clips it.
struct VoiceField: View {
    /// The width to draw at; the height follows the art's proportions.
    let width: CGFloat
    var showsBars = true
    /// Seconds into the cycle to draw instead of animating, for snapshots.
    var pinnedSeconds: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = VoiceFieldGeometry.size
        Group {
            if let pinnedSeconds {
                art(seconds: pinnedSeconds)
            } else if reduceMotion {
                art(seconds: nil)
            } else {
                TimelineView(.animation(minimumInterval: Motion.fieldFrameInterval)) { context in
                    art(seconds: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .scaleEffect(width / size.width, anchor: .topLeading)
        .frame(width: width, height: width * size.height / size.width, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The art at a moment of the cycle, or at rest when `seconds` is nil.
    private func art(seconds: Double?) -> some View {
        let size = VoiceFieldGeometry.size
        return ZStack(alignment: .topLeading) {
            field(progress: seconds.map { VoiceFieldGeometry.progress(atSeconds: $0) })
            if showsBars {
                bars
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Surface

    private func field(progress: Double?) -> some View {
        let size = VoiceFieldGeometry.size
        let wash = VoiceFieldGeometry.washBounds
        let outline = VoiceFieldGeometry.surface(at: progress ?? 0)
        let blend = progress.map { VoiceFieldGeometry.pigmentBlend(at: $0) }
        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Palette.Field.washA, location: 0),
                        .init(color: Palette.Field.washB, location: VoiceFieldGeometry.washMiddle),
                        .init(color: Palette.Field.washC, location: 1),
                    ],
                    startPoint: VoiceFieldGeometry.unit(VoiceFieldGeometry.washStart, in: wash),
                    endPoint: VoiceFieldGeometry.unit(VoiceFieldGeometry.washEnd, in: wash)
                ))
                .opacity(VoiceFieldGeometry.washOpacity)
                .frame(width: wash.width, height: wash.height)
                .offset(x: wash.minX, y: wash.minY)
            Circle()
                .stroke(Palette.Field.halo, lineWidth: VoiceFieldGeometry.haloWidth)
                .opacity(VoiceFieldGeometry.haloOpacity)
                .frame(width: wash.width, height: wash.height)
                .offset(x: wash.minX, y: wash.minY)
            surface(outline: outline, blend: blend)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask { LinearGradient(stops: VoiceFieldGeometry.horizontalFade, startPoint: .leading, endPoint: .trailing) }
        .mask { LinearGradient(stops: VoiceFieldGeometry.verticalFade, startPoint: .top, endPoint: .bottom) }
    }

    /// The violet-to-teal surface with its two pigments and the apricot highlight, clipped to
    /// the outline.
    private func surface(outline: [CGPoint], blend: Double?) -> some View {
        let size = VoiceFieldGeometry.size
        let layer = VoiceFieldGeometry.layer
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Palette.Field.surfaceA, location: 0),
                        .init(color: Palette.Field.surfaceB, location: VoiceFieldGeometry.surfaceMiddle),
                        .init(color: Palette.Field.surfaceC, location: 1),
                    ],
                    startPoint: VoiceFieldGeometry.unit(VoiceFieldGeometry.surfaceStart, in: layer),
                    endPoint: VoiceFieldGeometry.unit(VoiceFieldGeometry.surfaceEnd, in: layer)
                ))
                .frame(width: layer.width, height: layer.height)
                .offset(x: layer.minX, y: layer.minY)
            pigment(
                Palette.Field.violet,
                alpha: VoiceFieldGeometry.violetAlpha,
                center: VoiceFieldGeometry.violetCenter,
                radius: VoiceFieldGeometry.violetRadius,
                motion: VoiceFieldGeometry.violetMotion,
                blend: blend
            )
            pigment(
                Palette.Field.teal,
                alpha: VoiceFieldGeometry.tealAlpha,
                center: VoiceFieldGeometry.tealCenter,
                radius: VoiceFieldGeometry.tealRadius,
                motion: VoiceFieldGeometry.tealMotion,
                blend: blend
            )
            Rectangle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: Palette.Field.warmth.opacity(VoiceFieldGeometry.warmthAlpha), location: 0),
                        .init(color: Palette.Field.warmth.opacity(0), location: VoiceFieldGeometry.warmthFade),
                    ],
                    center: VoiceFieldGeometry.unit(VoiceFieldGeometry.warmthCenter, in: layer),
                    startRadius: 0,
                    endRadius: VoiceFieldGeometry.warmthRadius
                ))
                .frame(width: layer.width, height: layer.height)
                .offset(x: layer.minX, y: layer.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(VoiceFieldSurface(points: outline))
    }

    /// A soft pool of colour that turns and stretches a little about the art's centre. At rest
    /// (`blend` nil) it doesn't move.
    private func pigment(
        _ color: Color,
        alpha: Double,
        center: CGPoint,
        radius: CGFloat,
        motion: VoiceFieldGeometry.PigmentMotion,
        blend: Double?
    ) -> some View {
        let layer = VoiceFieldGeometry.layer
        let pivot = VoiceFieldGeometry.unit(VoiceFieldGeometry.pivot, in: layer)
        let move = motion.transform(at: blend ?? 0)
        return Rectangle()
            .fill(RadialGradient(
                gradient: Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                center: VoiceFieldGeometry.unit(center, in: layer),
                startRadius: 0,
                endRadius: radius
            ))
            .frame(width: layer.width, height: layer.height)
            .scaleEffect(x: blend == nil ? 1 : move.scaleX, y: blend == nil ? 1 : move.scaleY, anchor: pivot)
            .rotationEffect(.degrees(blend == nil ? 0 : move.rotation), anchor: pivot)
            .offset(x: layer.minX, y: layer.minY)
    }

    // MARK: Bars

    /// The five capsules: one gradient laid across all of them, cut to their shapes.
    private var bars: some View {
        let size = VoiceFieldGeometry.size
        let layer = VoiceFieldGeometry.barsLayer
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Palette.Field.barA, location: 0),
                        .init(color: Palette.Field.barB, location: VoiceFieldGeometry.barsMiddle),
                        .init(color: Palette.Field.barC, location: 1),
                    ],
                    startPoint: VoiceFieldGeometry.unit(VoiceFieldGeometry.barsStart, in: layer),
                    endPoint: VoiceFieldGeometry.unit(VoiceFieldGeometry.barsEnd, in: layer)
                ))
                .frame(width: layer.width, height: layer.height)
                .offset(x: layer.minX, y: layer.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask {
            ZStack(alignment: .topLeading) {
                ForEach(0..<VoiceFieldGeometry.bars.count, id: \.self) { index in
                    let bar = VoiceFieldGeometry.bars[index]
                    Capsule()
                        .frame(width: bar.width, height: bar.height)
                        .offset(x: bar.minX, y: bar.minY)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }
}
