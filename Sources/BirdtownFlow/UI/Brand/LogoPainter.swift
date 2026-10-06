import CoreGraphics
import SwiftUI

/// The Birdtown Flow logo, drawn from geometry and colours measured off the approved concept
/// (see `docs/brand.md`). This one painter feeds the .icns (`IconExporter`), the in-app
/// artwork (`AppIconArtwork`) and the spectrum disc, so the Dock icon, onboarding, About and
/// the dictation pill can never drift apart.
///
/// All lengths are fractions of the tile's side. The context must be y-down (SwiftUI's
/// `Canvas` is; `IconExporter` flips its bitmap context to match).
enum LogoPainter {
    /// Size-specific versions. Small icons get heavier bars and a lighter ring so the mark
    /// stays legible; at 16 px the ring goes entirely and three bars remain.
    enum Variant: Sendable {
        case full
        case medium
        case small
        case tiny

        /// The version for an icon canvas of `pixels` device pixels (tile plus Apple's margin).
        static func forCanvas(pixels: CGFloat) -> Variant {
            switch pixels {
            case ..<24: .tiny
            case ..<48: .small
            case ..<96: .medium
            default: .full
            }
        }
    }

    struct Geometry: Sendable {
        var showsRing: Bool
        var ringOuter: CGFloat
        var ringInner: CGFloat
        var barWidth: CGFloat
        var barPitch: CGFloat
        var barHeights: [CGFloat]

        /// Radius of the spectrum disc.
        var discRadius: CGFloat { showsRing ? ringInner : ringOuter }
    }

    static func geometry(_ variant: Variant) -> Geometry {
        switch variant {
        case .full:
            Geometry(showsRing: true, ringOuter: 0.3625, ringInner: 0.2853, barWidth: 0.0547, barPitch: 0.0925,
                     barHeights: [0.1149, 0.2193, 0.3332, 0.2193, 0.1149])
        case .medium:
            Geometry(showsRing: true, ringOuter: 0.3625, ringInner: 0.2853, barWidth: 0.062, barPitch: 0.098,
                     barHeights: [0.1149, 0.2193, 0.3332, 0.2193, 0.1149])
        case .small:
            Geometry(showsRing: true, ringOuter: 0.372, ringInner: 0.307, barWidth: 0.072, barPitch: 0.105,
                     barHeights: [0.13, 0.24, 0.36, 0.24, 0.13])
        case .tiny:
            Geometry(showsRing: false, ringOuter: 0.39, ringInner: 0.39, barWidth: 0.12, barPitch: 0.19,
                     barHeights: [0.24, 0.44, 0.24])
        }
    }

    /// Apple's macOS icon grid: the tile is 824 px of a 1024 px canvas, corners continuous.
    static let tileFraction: CGFloat = 824.0 / 1024.0
    static let cornerFraction: CGFloat = 0.2237

    /// The tile's square inside an icon canvas.
    static func tileRect(inCanvas canvas: CGRect) -> CGRect {
        let side = min(canvas.width, canvas.height) * tileFraction
        return CGRect(x: canvas.midX - side / 2, y: canvas.midY - side / 2, width: side, height: side)
    }

    static func tilePath(_ tile: CGRect) -> CGPath {
        Path(roundedRect: tile, cornerRadius: tile.width * cornerFraction, style: .continuous).cgPath
    }

    // MARK: - Drawing

    /// The whole icon: navy tile, ring, spectrum disc and bars.
    static func drawIcon(in cg: CGContext, tile: CGRect, variant: Variant) {
        let g = geometry(variant)
        let side = tile.width
        let centre = CGPoint(x: tile.midX, y: tile.midY)

        cg.saveGState()
        cg.addPath(tilePath(tile))
        cg.clip()
        drawTile(in: cg, tile: tile)
        if g.showsRing {
            drawRingShadow(in: cg, centre: centre, radius: g.ringOuter * side, side: side)
        }
        drawDisc(in: cg, centre: centre, radius: g.discRadius * side)
        if g.showsRing {
            drawRing(in: cg, centre: centre, outer: g.ringOuter * side, inner: g.ringInner * side)
        }
        drawBars(in: cg, centre: centre, side: side, geometry: g)
        cg.restoreGState()
    }

    /// The spectrum disc alone: hue by angle, blended toward a muted centre, deepening at the
    /// rim. `rotation` (radians) turns the hues, for the pill's slowly turning orb.
    static func drawDisc(in cg: CGContext, centre: CGPoint, radius: CGFloat, rotation: CGFloat = 0) {
        guard radius > 0 else { return }
        cg.saveGState()
        cg.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        cg.clip()

        // 1. Full-strength hues, as 1° wedges (each overlapping its neighbour so no seams show).
        drawWedges(in: cg, centre: centre, radius: radius * 1.02, stops: Colors.hueMid, rotation: rotation)

        // 2. The deeper rim hues, faded in over the outer band only.
        let reach = radius * Colors.blendReach
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        drawWedges(in: cg, centre: centre, radius: radius * 1.02, stops: Colors.hueRim, rotation: rotation)
        cg.setBlendMode(.destinationIn)
        if let mask = gradient([(0, CGColor(gray: 0, alpha: 0)), (1, CGColor(gray: 0, alpha: 1))]) {
            cg.drawRadialGradient(mask, startCenter: centre, startRadius: reach, endCenter: centre, endRadius: radius,
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        cg.endTransparencyLayer()

        // 3. The muted centre: the neutral at full strength in the middle, gone by `reach`.
        let neutral = Colors.centreNeutral
        let veil = stride(from: 0.0, through: 1.0, by: 0.1).map { s -> (CGFloat, CGColor) in
            (CGFloat(s), rgb(neutral, alpha: CGFloat(pow(1 - s, Colors.blendPower))))
        }
        if let veilGradient = gradient(veil) {
            cg.drawRadialGradient(veilGradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: reach,
                                  options: [])
        }
        cg.restoreGState()
    }

    private static func drawTile(in cg: CGContext, tile: CGRect) {
        let side = tile.width
        // Light from the top-left: a vertical fall-off, tilted slightly so the left is lighter.
        let tilt = Colors.tileTilt
        let start = CGPoint(x: tile.midX, y: tile.minY)
        let k = side / (1 + tilt * tilt)
        let end = CGPoint(x: start.x + tilt * k, y: start.y + k)
        if let body = gradient(Colors.tileStops.map { ($0.0, rgb($0.1)) }) {
            cg.drawLinearGradient(body, start: start, end: end,
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // A thin highlight along the top edge, the "subtle depth" of the concept.
        let rim = Colors.tileRim
        if let highlight = gradient([(0, rgb(rim, alpha: 0.65)), (0.5, rgb(rim, alpha: 0.16)), (1, rgb(rim, alpha: 0))]) {
            cg.drawLinearGradient(highlight, start: CGPoint(x: tile.midX, y: tile.minY),
                                  end: CGPoint(x: tile.midX, y: tile.minY + side * 0.03), options: [])
        }
    }

    private static func drawRingShadow(in cg: CGContext, centre: CGPoint, radius: CGFloat, side: CGFloat) {
        // Drawn as a soft disc rather than with CGContext shadows, whose offsets live in the
        // context's base space and so flip between bitmap and on-screen drawing.
        let blur = side * 0.013
        let shifted = CGPoint(x: centre.x, y: centre.y + side * 0.008)
        let shade = Colors.ringShadow
        if let soft = gradient([(0, rgb(shade, alpha: 0.55)), (1, rgb(shade, alpha: 0))]) {
            cg.drawRadialGradient(soft, startCenter: shifted, startRadius: max(0, radius - blur), endCenter: shifted,
                                  endRadius: radius + blur, options: [.drawsBeforeStartLocation])
        }
    }

    private static func drawRing(in cg: CGContext, centre: CGPoint, outer: CGFloat, inner: CGFloat) {
        cg.saveGState()
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: centre.x - outer, y: centre.y - outer, width: outer * 2, height: outer * 2))
        path.addEllipse(in: CGRect(x: centre.x - inner, y: centre.y - inner, width: inner * 2, height: inner * 2))
        cg.addPath(path)
        cg.clip(using: .evenOdd)
        if let fill = gradient([(0, rgb(Colors.ringTop)), (1, rgb(Colors.ringBottom))]) {
            cg.drawLinearGradient(fill, start: CGPoint(x: centre.x, y: centre.y - outer),
                                  end: CGPoint(x: centre.x, y: centre.y + outer), options: [])
        }
        cg.restoreGState()
    }

    private static func drawBars(in cg: CGContext, centre: CGPoint, side: CGFloat, geometry g: Geometry) {
        let width = g.barWidth * side
        let count = g.barHeights.count
        func capsule(index: Int, dy: CGFloat, grow: CGFloat) -> CGPath {
            let x = centre.x + (CGFloat(index) - CGFloat(count - 1) / 2) * g.barPitch * side
            let height = g.barHeights[index] * side
            let rect = CGRect(x: x - width / 2 - grow, y: centre.y - height / 2 + dy - grow,
                              width: width + grow * 2, height: height + grow * 2)
            return CGPath(roundedRect: rect, cornerWidth: rect.width / 2, cornerHeight: rect.width / 2, transform: nil)
        }
        // A faint two-step shadow below each bar.
        let shade = rgb(Colors.navyInk, alpha: 0.07)
        for step in [CGFloat(0.008), 0.004] {
            for index in 0..<count {
                cg.addPath(capsule(index: index, dy: side * 0.004, grow: side * step))
            }
            cg.setFillColor(shade)
            cg.fillPath()
        }
        for index in 0..<count {
            cg.addPath(capsule(index: index, dy: 0, grow: 0))
        }
        cg.setFillColor(rgb(Colors.barWhite))
        cg.fillPath()
    }

    private static func drawWedges(
        in cg: CGContext, centre: CGPoint, radius: CGFloat, stops: [UInt32], rotation: CGFloat
    ) {
        // Stops run counter-clockwise from +x in a y-up sense, every 360 / stops.count degrees.
        let colours = stops.map { rgbComponents($0) }
        for degree in 0..<360 {
            let a0 = (CGFloat(degree) - 0.4) * .pi / 180 + rotation
            let a1 = (CGFloat(degree) + 1.4) * .pi / 180 + rotation
            let mid = Double(degree) + 0.5
            let position = mid / (360.0 / Double(colours.count))
            let i0 = Int(position) % colours.count
            let i1 = (i0 + 1) % colours.count
            let t = CGFloat(position - floor(position))
            let c0 = colours[i0], c1 = colours[i1]
            cg.setFillColor(CGColor(srgbRed: c0.0 + (c1.0 - c0.0) * t, green: c0.1 + (c1.1 - c0.1) * t,
                                    blue: c0.2 + (c1.2 - c0.2) * t, alpha: 1))
            cg.move(to: centre)
            // y-down context: subtract the sine so angles still turn counter-clockwise on screen.
            cg.addLine(to: CGPoint(x: centre.x + radius * cos(a0), y: centre.y - radius * sin(a0)))
            cg.addLine(to: CGPoint(x: centre.x + radius * cos(a1), y: centre.y - radius * sin(a1)))
            cg.closePath()
            cg.fillPath()
        }
    }

    // MARK: - Colour helpers

    private static func rgbComponents(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        let c = rgbComponents(hex)
        return CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: alpha)
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map(\.1) as CFArray,
            locations: stops.map(\.0)
        )
    }

    // MARK: - Colors (measured from the approved concept)

    enum Colors {
        static let navyInk: UInt32 = 0x0E183C
        static let tileStops: [(CGFloat, UInt32)] = [(0, 0x263B6E), (0.10, 0x203569), (0.45, 0x0E183B), (1, 0x091231)]
        static let tileTilt: CGFloat = 0.12
        static let tileRim: UInt32 = 0x3A5794
        static let ringTop: UInt32 = 0xF8F9FD
        static let ringBottom: UInt32 = 0xF1F2F7
        static let ringShadow: UInt32 = 0x000416
        static let barWhite: UInt32 = 0xFEFCF8
        /// What the hues fade toward at the centre: a muted violet-grey.
        static let centreNeutral: UInt32 = 0x827596
        /// Fraction of the disc radius where the hues reach full strength.
        static let blendReach: CGFloat = 0.835
        static let blendPower: Double = 1.5
        /// Hues at full strength, every 10°, counter-clockwise from 3 o'clock.
        static let hueMid: [UInt32] = [
            0x54D896, 0x78DB83, 0x9BDA74, 0xBFD867, 0xDAD35D, 0xEBCC59,
            0xF6C25A, 0xFCB55F, 0xFEA964, 0xFE9D6C, 0xFE8E76, 0xFD8385,
            0xFB7896, 0xF76FA8, 0xEE65B9, 0xE35BC9, 0xD554D8, 0xC54DE5,
            0xB348ED, 0xA247F3, 0x9048F6, 0x814DF9, 0x6F54FB, 0x5F5BFC,
            0x5163FB, 0x456DFB, 0x3978FA, 0x3082F8, 0x2A8CF6, 0x2398F2,
            0x1EA4EC, 0x1CAFE6, 0x1BBBDB, 0x21C4CD, 0x2DCEBC, 0x3CD4AA,
        ]
        /// The deeper hues at the disc's edge.
        static let hueRim: [UInt32] = [
            0x3ED18D, 0x60D475, 0x8CD264, 0xB5CE57, 0xD3C74A, 0xE4BC43,
            0xEEB146, 0xF3A448, 0xF6964C, 0xF88752, 0xF8795E, 0xF86D6F,
            0xF36080, 0xEB5798, 0xE04DAC, 0xD346C1, 0xC63FD5, 0xB43AE2,
            0xA338EC, 0x9438F2, 0x853BF5, 0x7840F9, 0x6746FA, 0x544EFA,
            0x4459FC, 0x3762FB, 0x2E6EFA, 0x2777F8, 0x2081F6, 0x188CF5,
            0x0F98F3, 0x09A5EE, 0x07B2E5, 0x0BC0D6, 0x16C9C1, 0x26CDA7,
        ]
    }
}
