import SwiftUI

/// A small capsule label for something that *happened* to a dictation ("3 corrections",
/// "Polished · Claude") or a state ("Off"). Plain metadata belongs in text, not badges.
struct Badge: View {
    enum Tone { case neutral, accent, success, warning, danger }

    let text: String
    var symbol: String?
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(Typography.caption)
        .foregroundStyle(foreground)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xxs)
        .background(Capsule().fill(background))
        .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Palette.inkSecondary
        case .accent: Palette.accent
        case .success: Palette.success
        case .warning: Palette.warning
        case .danger: Palette.danger
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: Palette.sunken
        case .accent: Palette.accentSoft
        case .success: Palette.successSoft
        case .warning: Palette.warningSoft
        case .danger: Palette.dangerSoft
        }
    }
}
