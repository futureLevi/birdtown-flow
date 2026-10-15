import SwiftUI

/// A caption above a text field, with the 3 pt focus ring while focused. Used by the
/// dictionary and snippet sheets; fits any form that wants the app's inset field.
struct LabeledInput: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    /// Takes keyboard focus when it appears: the first field of a dialog.
    var autofocus = false

    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
            TextField(label, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .focused($isFocused)
                .padding(.horizontal, Spacing.m)
                .frame(height: Layout.Main.searchFieldHeight)
                .background(shape.fill(Palette.surface))
                .overlay(shape.strokeBorder(Palette.hairlineStrong, lineWidth: Layout.Main.hairline))
                .flowFocusRing(shape, drawn: isFocused)
        }
        .onAppear {
            guard autofocus else { return }
            // Deferred: a sheet's first layout pass hasn't made the field focusable yet.
            Task { @MainActor in isFocused = true }
        }
    }
}
