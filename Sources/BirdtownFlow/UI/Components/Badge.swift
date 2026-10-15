import SwiftUI

/// A small label (6 pt corners, 15 pt text) for something that *happened* to a dictation
/// ("3 replacements", "Polished · Claude") or a state ("Off"). Plain metadata belongs in text,
/// not badges. Violet marks polish and tuning, teal marks vocabulary; the rest are state.
struct Badge: View {
    enum Tone { case neutral, accent, violet, teal, success, warning, danger }

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
        .padding(.vertical, Spacing.xs)
        .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(background))
        .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Palette.inkSecondary
        case .accent: Palette.accentInk
        case .violet: Palette.violet
        case .teal: Palette.teal
        case .success: Palette.success
        case .warning: Palette.warning
        case .danger: Palette.danger
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: Palette.chip
        case .accent: Palette.accentSoft
        case .violet: Palette.violetSoft
        case .teal: Palette.tealSoft
        case .success: Palette.successSoft
        case .warning: Palette.warningSoft
        case .danger: Palette.dangerSoft
        }
    }
}
