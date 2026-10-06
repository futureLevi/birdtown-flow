import SwiftUI

// MARK: - App icon

/// The app icon, drawn in code. `Tools/makeicon.swift` carries an identical copy of
/// `AppIconPainter` (the script can't import the app), so the .icns and this view match.
/// If you change one, paste it into the other; the `brand-*` snapshots show the result.
struct AppIconArtwork: View {
    var size: CGFloat = 128
    /// Off for exports, where the page supplies its own context.
    var showsShadow = true

    var body: some View {
        Canvas { context, canvasSize in
            context.withCGContext { cg in
                AppIconPainter.draw(in: cg, side: canvasSize.width)
            }
        }
        .frame(width: size, height: size)
        // The same soft shadow the .icns bakes in, so the tile sits on the page.
        .shadow(color: .black.opacity(showsShadow ? 0.3 : 0), radius: size * 0.014, y: size * 0.01)
        .accessibilityLabel("Murmur")
    }
}

// BEGIN AppIconPainter — keep identical in Tools/makeicon.swift
enum AppIconPainter {
    /// Draws the icon into a square of `side` points in a y-down context: an ink squircle
    /// lit from above, a warm paper glow rising from below, and a waveform whose centre bar
    /// is Ember. Below 64 px the mark drops to three heavier bars so it still reads.
    static func draw(in cg: CGContext, side: CGFloat) {
        let inset = side * 100 / 1024
        let tile = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let radius = tile.width * 0.225
        let shape = squircle(tile, radius: radius)
        let small = side < 64

        // Body: warm ink, a touch lighter at the top.
        cg.saveGState()
        cg.addPath(shape)
        cg.clip()
        linear(cg, [rgb(0x2E2C29), rgb(0x141312)], from: CGPoint(x: tile.midX, y: tile.minY),
               to: CGPoint(x: tile.midX, y: tile.maxY))
        // Warm paper glow rising from below the mark.
        radial(cg, [rgb(0xF7E6D0, 0.20), rgb(0xF7E6D0, 0.06), rgb(0xF7E6D0, 0)], locations: [0, 0.5, 1],
               centre: CGPoint(x: tile.midX, y: tile.minY + tile.height * 0.68), radius: tile.width * 0.7)
        // Ember warmth right behind the voice.
        radial(cg, [rgb(0xFF6A3D, 0.30), rgb(0xFF6A3D, 0.08), rgb(0xFF6A3D, 0)], locations: [0, 0.45, 1],
               centre: CGPoint(x: tile.midX, y: tile.midY), radius: tile.width * 0.36)
        cg.restoreGState()

        // A hairline rim, bright at the top, so the tile reads as an object on dark docks.
        if !small {
            let width = side * 0.005
            cg.saveGState()
            cg.addPath(squircle(tile.insetBy(dx: width / 2, dy: width / 2), radius: radius - width / 2))
            cg.setLineWidth(width)
            cg.replacePathWithStrokedPath()
            cg.clip()
            linear(cg, [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0.04)], from: CGPoint(x: tile.midX, y: tile.minY),
                   to: CGPoint(x: tile.midX, y: tile.maxY))
            cg.restoreGState()
        }

        // The mark.
        let heights: [CGFloat] = small ? [0.56, 1, 0.56] : [0.34, 0.62, 1, 0.62, 0.34]
        let barWidth = tile.width * (small ? 0.13 : 0.082)
        let gap = tile.width * (small ? 0.09 : 0.06)
        let tallest = tile.height * (small ? 0.5 : 0.46)
        let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        let centreIndex = heights.count / 2
        for (index, fraction) in heights.enumerated() {
            let height = max(barWidth, tallest * fraction)
            let x = tile.midX - total / 2 + CGFloat(index) * (barWidth + gap)
            let bar = CGRect(x: x, y: tile.midY - height / 2, width: barWidth, height: height)
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
            cg.clip()
            let colours = index == centreIndex ? [rgb(0xFF8A5C), rgb(0xE5532A)] : [rgb(0xFBF8F2), rgb(0xE6DFD3)]
            linear(cg, colours, from: CGPoint(x: bar.midX, y: bar.minY), to: CGPoint(x: bar.midX, y: bar.maxY))
            cg.restoreGState()
        }
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func linear(_ cg: CGContext, _ colours: [CGColor], from start: CGPoint, to end: CGPoint) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: nil)
        else { return }
        cg.drawLinearGradient(gradient, start: start, end: end,
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func radial(_ cg: CGContext, _ colours: [CGColor], locations: [CGFloat], centre: CGPoint, radius: CGFloat) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: locations)
        else { return }
        cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius,
                              options: [])
    }

    /// Continuous-curvature rounded rectangle (the "squircle" of Apple's icon grid).
    static func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, min(rect.width, rect.height) / 2 / 1.52866483)
        func tl(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * r, y: rect.minY + y * r) }
        func tr(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.maxX - x * r, y: rect.minY + y * r) }
        func br(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.maxX - x * r, y: rect.maxY - y * r) }
        func bl(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * r, y: rect.maxY - y * r) }
        let path = CGMutablePath()
        path.move(to: tl(1.52866483, 0))
        path.addLine(to: tr(1.52866471, 0))
        path.addCurve(to: tr(0.66993427, 0.06549600), control1: tr(1.08849323, 0), control2: tr(0.86840689, 0))
        path.addLine(to: tr(0.63149399, 0.07491100))
        path.addCurve(to: tr(0.07491176, 0.63149399), control1: tr(0.37282392, 0.16905899), control2: tr(0.16906013, 0.37282401))
        path.addCurve(to: tr(0, 1.52866483), control1: tr(0, 0.86840701), control2: tr(0, 1.08849299))
        path.addLine(to: br(0, 1.52866471))
        path.addCurve(to: br(0.06549569, 0.66993493), control1: br(0, 1.08849323), control2: br(0, 0.86840689))
        path.addLine(to: br(0.07491111, 0.63149399))
        path.addCurve(to: br(0.63149399, 0.07491111), control1: br(0.16905883, 0.37282392), control2: br(0.37282392, 0.16905883))
        path.addCurve(to: br(1.52866471, 0), control1: br(0.86840689, 0), control2: br(1.08849323, 0))
        path.addLine(to: bl(1.52866483, 0))
        path.addCurve(to: bl(0.66993397, 0.06549569), control1: bl(1.08849299, 0), control2: bl(0.86840701, 0))
        path.addLine(to: bl(0.63149399, 0.07491111))
        path.addCurve(to: bl(0.07491100, 0.63149399), control1: bl(0.37282401, 0.16905883), control2: bl(0.16906001, 0.37282392))
        path.addCurve(to: bl(0, 1.52866471), control1: bl(0, 0.86840689), control2: bl(0, 1.08849323))
        path.addLine(to: tl(0, 1.52866483))
        path.addCurve(to: tl(0.06549600, 0.66993397), control1: tl(0, 1.08849299), control2: tl(0, 0.86840701))
        path.addLine(to: tl(0.07491100, 0.63149399))
        path.addCurve(to: tl(0.63149399, 0.07491100), control1: tl(0.16906001, 0.37282401), control2: tl(0.37282401, 0.16906001))
        path.addCurve(to: tl(1.52866483, 0), control1: tl(0.86840701, 0), control2: tl(1.08849299, 0))
        path.closeSubpath()
        return path
    }
}
// END AppIconPainter

// MARK: - Marks

/// The Murmur mark: five bars, centre in Ember. For onboarding, About and empty states.
struct BrandMark: View {
    var height: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: height * BrandGeometry.gap) {
            ForEach(BrandGeometry.heights.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == BrandGeometry.heights.count / 2 ? Palette.ember : Palette.ink)
                    .frame(width: height * BrandGeometry.barWidth, height: height * BrandGeometry.heights[index])
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Monochrome mark for the menu bar (or anywhere a template glyph is needed). Draws in the
/// current foreground style, so it follows the menu bar's appearance. `isActive` lifts the
/// bars while recording.
struct BrandGlyph: View {
    var size: CGFloat = 16
    var isActive = false

    var body: some View {
        let heights = isActive ? BrandGeometry.activeHeights : BrandGeometry.heights
        HStack(alignment: .center, spacing: size * BrandGeometry.gap) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .frame(width: size * BrandGeometry.barWidth, height: size * heights[index] * 0.82)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Murmur")
    }
}

/// Mark plus name, in the serif display face.
struct BrandWordmark: View {
    var height: CGFloat = 22

    var body: some View {
        HStack(spacing: height * 0.45) {
            BrandMark(height: height)
            Text("Murmur")
                .font(Typography.title)
                .tracking(Tracking.title)
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Murmur")
    }
}

private enum BrandGeometry {
    static let heights: [CGFloat] = [0.34, 0.62, 1, 0.62, 0.34]
    static let activeHeights: [CGFloat] = [0.5, 0.86, 1, 0.74, 0.44]
    static let barWidth: CGFloat = 0.12
    static let gap: CGFloat = 0.1
}
