import Foundation

/// The Home hero's motion, "Shimmer", as plain functions of time and position so any renderer
/// can draw it and tests can pin it down. Positions are in the hero's 660 x 150 pt design
/// space, times in seconds.
///
/// - Shimmer: the lines hold still while a soft band of light glides across them, left to
///   right, in `sweepDuration`, once every `sweepInterval`. Lines under the band brighten and
///   grow by up to `heightLift`.
/// - Opening: once, as Home appears, the voice rises from left to right in `openingDuration`.
///
/// The numbers are the approved motion mock's (Voiceprint in Motion, October 2026).
public enum VoiceprintMotion {
    public static let sweepDuration: Double = 2.8
    /// From the start of one sweep to the start of the next.
    public static let sweepInterval: Double = 7.5
    /// The still pause between two sweeps.
    public static var restDuration: Double { sweepInterval - sweepDuration }
    /// The band is a gaussian this wide (its sigma, in points).
    public static let bandSigma: Double = 26
    /// Where the band's centre starts and ends: from under the end of the greeting, where the
    /// voice is a whisper, to the hero's right edge.
    public static let bandStartX: Double = 240
    public static let bandEndX: Double = 660
    /// How much taller a line grows at the centre of the band.
    public static let heightLift: Double = 0.045

    /// The opening: each line takes `openingRise` to rise, and the rise starts later the further
    /// right the line is, by up to `openingStagger` across `openingSpanX`.
    public static let openingStartX: Double = 199
    public static let openingSpanX: Double = 430
    public static let openingStagger: Double = 0.55
    public static let openingRise: Double = 0.85
    public static var openingDuration: Double { openingStagger + openingRise }

    /// The band's centre `t` seconds into a sweep, or nil when no sweep is running.
    public static func bandCenter(at t: Double) -> Double? {
        guard t >= 0, t < sweepDuration else { return nil }
        return bandStartX + (bandEndX - bandStartX) * smoothstep(t / sweepDuration)
    }

    /// How strongly the band lights a line at `x`, 0...1, `t` seconds into a sweep.
    public static func sheen(x: Double, sweepTime t: Double) -> Double {
        guard let center = bandCenter(at: t) else { return 0 }
        let distance = (x - center) / bandSigma
        return exp(-distance * distance)
    }

    /// A line's height, relative to its resting height, under a band of strength `sheen`.
    public static func heightFactor(sheen: Double) -> Double {
        1 + heightLift * sheen
    }

    /// How far a line at `x` has risen, 0...1, `t` seconds into the opening.
    public static func opening(x: Double, at t: Double) -> Double {
        let delay = (x - openingStartX) / openingSpanX * openingStagger
        return easeOutCubic((t - delay) / openingRise)
    }

    public static func smoothstep(_ t: Double) -> Double {
        let t = clamp(t)
        return t * t * (3 - 2 * t)
    }

    public static func easeOutCubic(_ t: Double) -> Double {
        let t = clamp(t)
        let rest = 1 - t
        return 1 - rest * rest * rest
    }

    public static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
        min(upper, max(lower, value))
    }
}
