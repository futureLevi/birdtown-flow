import SwiftUI

/// Determinate progress in the logo's spectrum, for model downloads: one of the few places
/// the spectrum belongs, because something is actively arriving. `nil` progress draws the
/// empty track, so an unknown size never pretends to be moving.
struct SpectrumProgressBar: View {
    let progress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(progress ?? 0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken)
                if fraction > 0 {
                    Capsule()
                        .fill(Spectrum.progress)
                        .frame(width: max(proxy.size.height, proxy.size.width * fraction))
                }
            }
        }
        .frame(height: Layout.Main.progressBarHeight)
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Download progress")
        .accessibilityValue(Text(progress ?? 0, format: .percent.precision(.fractionLength(0))))
    }
}
