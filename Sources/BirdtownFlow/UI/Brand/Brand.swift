import SwiftUI

// The Birdtown Flow brand in views. Everything here draws through `LogoPainter`, the same code
// that renders the .icns, so the Dock icon, onboarding, About and the menu bar match exactly.

// MARK: - App icon

/// The app icon at any size, with Apple's icon margin around the tile.
struct AppIconArtwork: View {
    var size: CGFloat = 128
    /// Off for exports, where the page supplies its own context.
    var showsShadow = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let tileSide = size * LogoPainter.tileFraction
        Canvas { context, canvasSize in
            let canvas = CGRect(origin: .zero, size: canvasSize)
            let tile = LogoPainter.tileRect(inCanvas: canvas)
            let variant = LogoPainter.Variant.forCanvas(pixels: canvasSize.width * displayScale)
            context.withCGContext { cg in
                LogoPainter.drawIcon(in: cg, tile: tile, variant: variant)
            }
        }
        .frame(width: size, height: size)
        // On a midnight-navy window the tile's dark lower edge would vanish; a faint rim keeps
        // it reading as an object. Light appearance needs nothing.
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: tileSide * LogoPainter.cornerFraction, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: max(0.5, size / 256))
                    .frame(width: tileSide, height: tileSide)
            }
        }
        // The soft shadow the .icns bakes in, so the tile sits on the page.
        .shadow(color: .black.opacity(showsShadow ? 0.28 : 0), radius: size * 0.016, y: size * 0.01)
        .accessibilityLabel("Birdtown Flow")
    }
}

// MARK: - Bars

/// The logo's five bars, mirrored, in its exact proportions. Height is the tallest bar.
struct LogoBars: Shape {
    /// Bar heights relative to the tallest, and width and pitch relative to the tallest bar.
    static let heights: [CGFloat] = [0.345, 0.658, 1, 0.658, 0.345]
    static let width: CGFloat = 0.164
    static let pitch: CGFloat = 0.278

    /// Width of the whole group for a given height.
    static func groupWidth(height: CGFloat) -> CGFloat {
        (CGFloat(heights.count - 1) * pitch + width) * height
    }

    func path(in rect: CGRect) -> Path {
        let height = rect.height
        let barWidth = Self.width * height
        let total = Self.groupWidth(height: height)
        var path = Path()
        for (index, fraction) in Self.heights.enumerated() {
            let x = rect.midX - total / 2 + CGFloat(index) * Self.pitch * height
            let barHeight = fraction * height
            path.addRoundedRect(
                in: CGRect(x: x, y: rect.midY - barHeight / 2, width: barWidth, height: barHeight),
                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
            )
        }
        return path
    }
}

// MARK: - Marks

/// The bars alone, in ink. For the wordmark, About and empty states.
struct BrandMark: View {
    var height: CGFloat = 28

    var body: some View {
        LogoBars()
            .fill(Palette.ink)
            .frame(width: LogoBars.groupWidth(height: height), height: height)
            .accessibilityHidden(true)
    }
}

/// Monochrome bars wherever a template glyph is needed. Draws in the current foreground style,
/// so it follows the appearance. `isActive` adds the spectrum dot used while recording.
struct BrandGlyph: View {
    var size: CGFloat = 16
    var isActive = false

    var body: some View {
        LogoBars()
            .frame(width: LogoBars.groupWidth(height: size * 0.9), height: size * 0.9)
            .frame(width: size * 1.2, height: size)
            .overlay(alignment: .topTrailing) {
                if isActive {
                    SpectrumOrb(mode: .still, diameter: max(Layout.Orb.small, size * 0.4))
                        .offset(x: size * 0.12, y: -size * 0.08)
                }
            }
            .accessibilityLabel("Birdtown Flow")
    }
}

/// Mark plus name.
struct BrandWordmark: View {
    var height: CGFloat = 22

    var body: some View {
        HStack(spacing: height * 0.45) {
            BrandMark(height: height)
            Text("Birdtown Flow")
                .font(Typography.title)
                .tracking(Tracking.title)
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Birdtown Flow")
    }
}
