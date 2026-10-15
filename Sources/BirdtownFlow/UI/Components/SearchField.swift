import SwiftUI

/// A search field with a magnifier, a clear button, Esc to clear and ⌘F to focus. Keyboard
/// focus shows the 3 pt ring outside it.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    /// When set, the field takes focus whenever this turns true (and clears it): the
    /// toolbar's "Search history" asks History's field this way, even if History wasn't
    /// showing yet.
    var focusRequest: Binding<Bool>?

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.inkSecondary)
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
        .background(shape.fill(Palette.surface))
        .overlay(shape.strokeBorder(Palette.hairlineStrong, lineWidth: Layout.Main.hairline))
        .contentShape(shape)
        .flowFocusRing(shape, drawn: isFocused)
        .onTapGesture { isFocused = true }
        .onChange(of: focusRequest?.wrappedValue ?? false) { _, requested in
            guard requested, let focusRequest else { return }
            focusRequest.wrappedValue = false
            isFocused = true
        }
        .onAppear {
            // A request made before this field existed (Search history from another page).
            guard let focusRequest, focusRequest.wrappedValue else { return }
            focusRequest.wrappedValue = false
            Task { @MainActor in isFocused = true }
        }
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
