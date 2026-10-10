import SwiftUI

/// The navy band at the top of Home: the app icon's tile, stretched wide, with the Voiceprint
/// on its right and the page's own words (the greeting and a hint) on its left.
struct VoiceprintHero<Content: View>: View {
    /// How wide the words may run before they reach the full-strength voice.
    struct Room {
        var greeting: CGFloat
        var hint: CGFloat
    }

    /// Seconds into a Shimmer sweep to draw instead of animating, for snapshots.
    var sweepPhase: Double?
    @ViewBuilder var content: (Room) -> Content

    @Environment(\.colorScheme) private var colorScheme
    @State private var width = Layout.Hero.designWidth
    @State private var isOnScreen = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.Hero.cornerRadius, style: .continuous)
        let scale = min(1, width / Layout.Hero.designWidth)
        // Where the art's left edge lands: extra width is calm room for the words.
        let artLeft = width - Layout.Hero.designWidth * scale
        let room = Room(
            greeting: artLeft + Layout.Hero.greetingEndX * scale - Layout.Hero.textInset,
            hint: artLeft + Layout.Hero.hintEndX * scale - Layout.Hero.textInset
        )

        shape
            .fill(LinearGradient(stops: Palette.Hero.ground, startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .trailing) {
                VoiceprintArt(sweepPhase: sweepPhase, isOnScreen: isOnScreen)
                    .scaleEffect(x: scale, y: 1, anchor: .trailing)
            }
            .overlay(alignment: .leading) {
                content(room)
                    .padding(.leading, Layout.Hero.textInset)
            }
            // Keeps the art's screen blending inside the tile.
            .compositingGroup()
            .clipShape(shape)
            .overlay { shape.strokeBorder(Palette.Hero.edge, lineWidth: Layout.Hero.edge) }
            .frame(height: Layout.Hero.height)
            .frame(maxWidth: .infinity)
            .background {
                if colorScheme == .light {
                    shape
                        .fill(Palette.Hero.shadow)
                        .elevation(Elevation.heroContact)
                        .elevation(Elevation.heroLift)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
            .onScrollVisibilityChange(threshold: 0.01) { isOnScreen = $0 }
    }
}
