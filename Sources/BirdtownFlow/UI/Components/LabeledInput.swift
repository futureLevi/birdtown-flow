import SwiftUI

/// A caption above an inset text field. Used by the dictionary and snippet sheets;
/// fits any form that wants Murmur's inset field.
struct LabeledInput: View {
    let label: String
    @Binding var text: String
    var prompt = ""

    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkSecondary)
            TextField(label, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .focused($isFocused)
                .padding(.horizontal, Spacing.m)
                .frame(height: Layout.Main.searchFieldHeight)
                .background(shape.fill(Palette.sunken))
                .overlay(shape.strokeBorder(isFocused ? Palette.hairlineStrong : Palette.hairline,
                                            lineWidth: Layout.Main.hairline))
        }
    }
}
