import Accessibility
import SwiftUI

/// "Snippet deleted · Undo": a capsule floating over the bottom of a page while a delete
/// waits out its undo window (`Motion.undoWindow`). Drawn like History's undo toast, with
/// the same ⌘Z, so every list in the app undoes a delete the same way.
///
/// Put it in a page's bottom overlay; it draws nothing while `message` is `nil`.
struct UndoToast: View {
    /// What was deleted, e.g. "Snippet deleted". `nil` hides the toast.
    let message: String?
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let message {
            HStack(spacing: Spacing.m) {
                Image(systemName: "trash")
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                Text(message)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Undo", action: onUndo)
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityHint("Command-Z")
            }
            .padding(.leading, Spacing.l)
            .padding(.trailing, Spacing.s)
            .padding(.vertical, Spacing.s)
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline))
            .elevation(Elevation.raised)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
            .transition(reduceMotion ? AnyTransition.opacity
                                     : AnyTransition.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Tells VoiceOver about a delete, since the toast is easy to miss without sight and only
    /// lasts the undo window.
    @MainActor
    static func announce(_ message: String) {
        AccessibilityNotification.Announcement("\(message). Press Command-Z to undo.").post()
    }
}
