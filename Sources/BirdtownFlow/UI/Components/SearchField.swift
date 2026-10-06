import SwiftUI

/// A search well with a magnifier, a clear button, Esc to clear and ⌘F to focus.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isFocused ? Palette.inkSecondary : Palette.inkTertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .focused($isFocused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.inkTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: Layout.Main.searchFieldHeight)
        .background(shape.fill(Palette.sunken))
        .overlay(shape.strokeBorder(isFocused ? Palette.accent : Palette.hairline,
                                    lineWidth: isFocused ? Layout.Main.focusRing : Layout.Main.hairline))
        .contentShape(shape)
        .onTapGesture { isFocused = true }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: text.isEmpty)
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isFocused)
        .background {
            // ⌘F focuses the field, as it does in every Mac app with search.
            Button("Find") { isFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
