import Accessibility
import MurmurKit
import SwiftUI

/// A capsule floating over the bottom of a page: the undo toast and History's selection bar.
/// Items sit `Spacing.xs` apart because the ghost buttons carry their own padding; a wider
/// stack spacing would leave bigger gaps between two buttons than beside the label. The bar
/// always takes its ideal width, so no button label is ever elided ("Delet…").
/// Pages that show it inset their scroll content by `Layout.Main.floatingBarClearance`.
struct HistoryFloatingBar<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            content
        }
        .fixedSize()
        .padding(.leading, Spacing.l)
        .padding(.trailing, Spacing.s)
        .padding(.vertical, Spacing.s)
        .background(Capsule().fill(Palette.surface))
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline))
        .elevation(Elevation.raised)
        .padding(.bottom, Spacing.xl)
        .transition(reduceMotion ? AnyTransition.opacity
                                 : AnyTransition.move(edge: .bottom).combined(with: .opacity))
    }
}

/// "Dictation deleted · Undo" while a History delete waits out its undo window. Home and
/// History both show it, reading the shared `AppModel.historyDeletion`, so a delete made on
/// either page can be undone from either (⌘Z included).
struct HistoryUndoToast: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.historyDeletion.pending.count
        if count > 0 {
            HistoryFloatingBar {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "trash")
                        .foregroundStyle(Palette.inkSecondary)
                    Text(count == 1 ? "Dictation deleted" : "\(count) dictations deleted")
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                }
                Button("Undo") { model.historyDeletion.undo() }
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityHint("Command-Z")
            }
        }
    }

    /// Deletes `ids` with undo and says so to VoiceOver, since the toast is easy to miss
    /// without sight and only lasts the undo window. Stops their audio if it's playing.
    @MainActor
    static func delete(_ ids: Set<UUID>, model: AppModel, player: AudioPlayback) {
        guard !ids.isEmpty else { return }
        if let playing = player.playingID, ids.contains(playing) { player.stop() }
        model.historyDeletion.delete(ids)
        let announcement: String = ids.count == 1
            ? "Dictation deleted. Press Command-Z to undo."
            : "\(ids.count) dictations deleted. Press Command-Z to undo."
        AccessibilityNotification.Announcement(announcement).post()
    }
}
