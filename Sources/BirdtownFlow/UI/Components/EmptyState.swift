import SwiftUI

/// A warm, specific empty state: what's missing, why, and the one thing to do about it.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(Typography.title)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: Layout.Main.emptyStateBadge, height: Layout.Main.emptyStateBadge)
                .background(Circle().fill(Palette.sunken))
                .padding(.bottom, Spacing.xs)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.title)
                .tracking(Tracking.title)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(Spacing.xxs)
                .frame(maxWidth: Layout.Main.emptyStateTextWidth)
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, Spacing.s)
        }
        .padding(.vertical, Spacing.huge)
        .padding(.horizontal, Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
