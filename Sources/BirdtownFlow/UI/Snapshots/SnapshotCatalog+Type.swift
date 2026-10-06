import SwiftUI

// The title-font exploration: a specimen of every treatment side by side, and the screens
// where the large text matters most, re-rendered under each treatment.
extension SnapshotCatalog {
    /// Screens to compare. The default treatment already appears in the normal shots, so
    /// only the others are rendered again, as `type-<treatment>-<screen>`.
    static func typeTreatments(from screens: [SnapshotRenderer.Shot]) -> [SnapshotRenderer.Shot] {
        let compared = ["home", "setup-onboarding-1-welcome", "style", "history"]
        var shots = [SnapshotRenderer.Shot("type-specimen", size: TypeSpecimen.size) { TypeSpecimen() }]
        for treatment in TypeTreatment.allCases where treatment != .default {
            for name in compared {
                guard let screen = screens.first(where: { $0.name == name }) else { continue }
                shots.append(screen.with(name: "type-\(treatment.rawValue)-\(name)", treatment: treatment))
            }
        }
        return shots
    }
}

/// Each treatment's large faces on the same words, drawn a quarter larger than in the app so
/// the letterforms can be judged in a 1x render.
struct TypeSpecimen: View {
    static let scale: CGFloat = 1.25
    static let rowHeight: CGFloat = 200
    static let size = CGSize(width: 1480, height: rowHeight * CGFloat(TypeTreatment.allCases.count) + 64)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(TypeTreatment.allCases) { treatment in
                row(treatment)
                    .frame(height: Self.rowHeight)
                if treatment != TypeTreatment.allCases.last {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, Spacing.xxxl)
        .padding(.vertical, Spacing.xxxl)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Palette.canvas)
    }

    private func row(_ treatment: TypeTreatment) -> some View {
        let faces = treatment.faces(scale: Self.scale)
        return HStack(alignment: .center, spacing: Spacing.huge) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(treatment.displayName)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                Text(treatment == .default ? "In the nightly by default" : "Try it in Settings")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .frame(width: 170, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Birdtown Flow")
                    .font(faces.hero)
                    .tracking(faces.displayTracking)
                Text("Good evening, Levi")
                    .font(faces.display)
                    .tracking(faces.displayTracking)
            }
            .foregroundStyle(Palette.ink)
            .frame(width: 520, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxl) {
                    stat("226", unit: "words", faces: faces)
                    stat("150", unit: "wpm", faces: faces)
                    stat("6", unit: "days", faces: faces)
                }
                Text("Personal messages")
                    .font(faces.title)
                    .tracking(faces.titleTracking)
                    .foregroundStyle(Palette.ink)
                Text("Running ten minutes late, grab us a table by the window if you can")
                    .font(.system(size: 15 * Self.scale))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func stat(_ value: String, unit: String, faces: TypeFaces) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(value)
                .font(faces.numeral)
                .foregroundStyle(Palette.ink)
            Text(unit)
                .font(faces.statUnit)
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}
