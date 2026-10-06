import AppKit
import CoreGraphics

/// `BirdtownFlow --export-icon <AppIcon.iconset> [preview.png]` renders every icon size from
/// `LogoPainter`, choosing the size-specific variant for each, with the macOS drop shadow baked
/// in. `make icon` (and CI) turn the set into `AppIcon.icns` with `iconutil`.
@MainActor
enum IconExporter {
    /// iconutil's expected names and pixel sizes.
    static let sizes: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func run(iconset: URL, preview: URL?) -> Int32 {
        do {
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            for size in sizes {
                try png(pixels: size.pixels).write(to: iconset.appendingPathComponent("\(size.name).png"))
            }
            if let preview {
                try FileManager.default.createDirectory(
                    at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png(pixels: 1024).write(to: preview)
            }
            // Bare tiles at review sizes, for comparing against the concept.
            print("[icon] wrote \(sizes.count) sizes to \(iconset.path)")
            return 0
        } catch {
            print("[icon] failed: \(error.localizedDescription)")
            return 1
        }
    }

    enum ExportError: LocalizedError {
        case context
        case encoding

        var errorDescription: String? {
            switch self {
            case .context: "Couldn't create a bitmap context."
            case .encoding: "Couldn't encode the PNG."
            }
        }
    }

    /// One icon image, `pixels` square.
    static func png(pixels: Int) throws -> Data {
        let side = CGFloat(pixels)
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let cg = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ExportError.context }

        cg.interpolationQuality = .high
        cg.setShouldAntialias(true)
        // LogoPainter draws y-down, like SwiftUI; bitmap contexts are y-up.
        cg.translateBy(x: 0, y: side)
        cg.scaleBy(x: 1, y: -1)

        let tile = LogoPainter.tileRect(inCanvas: CGRect(x: 0, y: 0, width: side, height: side))

        // The drop shadow macOS icons carry in their artwork. Shadow offsets are in base space
        // (y-up here), so a negative height falls downward on screen.
        cg.saveGState()
        cg.setShadow(
            offset: CGSize(width: 0, height: -side * 10 / 1024),
            blur: side * 24 / 1024,
            color: CGColor(gray: 0, alpha: 0.32)
        )
        cg.addPath(LogoPainter.tilePath(tile))
        cg.setFillColor(LogoPainter.rgb(LogoPainter.Colors.navyInk))
        cg.fillPath()
        cg.restoreGState()

        LogoPainter.drawIcon(in: cg, tile: tile, variant: .forCanvas(pixels: side))

        guard let image = cg.makeImage() else { throw ExportError.context }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw ExportError.encoding }
        return data
    }
}
