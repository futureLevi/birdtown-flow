import MurmurKit
import SwiftUI

/// Snippets: say a trigger phrase, get the expansion typed.
struct SnippetsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var isAdding = false
    @State private var editing: Snippet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let store = model.snippets
        let uses = LibraryUsage.snippetCounts(
            snippets: store.snippets, aliases: store.aliases, records: model.history.records)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Snippets waiting out a delete's undo window are hidden.
        let visible = store.visible.filter {
            trimmed.isEmpty || $0.trigger.localizedStandardContains(trimmed) || $0.expansion.localizedStandardContains(trimmed)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                PageHeader(title: "Snippets", subtitle: "Say the trigger and Birdtown Flow types the expansion.") {
                    Button {
                        isAdding = true
                    } label: {
                        Label("New Snippet", systemImage: "plus")
                    }
                    .buttonStyle(.flowSecondary)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Add a snippet (⌘N)")
                }

                if store.visible.isEmpty {
                    EmptyState(
                        symbol: "text.badge.plus",
                        title: "Stop typing the same things",
                        message: "Your scheduling link, your address, a sign-off. Give each a short phrase "
                            + "and say it whenever you need it."
                    ) {
                        Button("New Snippet") { isAdding = true }
                            .buttonStyle(.flowSecondary)
                    }
                    .cardSurface()
                } else {
                    SearchField(text: $query, prompt: "Search snippets")
                        .frame(maxWidth: Layout.Main.searchFieldWidth)
                    if visible.isEmpty {
                        EmptyState(
                            symbol: "magnifyingglass",
                            title: "No snippets match “\(trimmed)”",
                            message: "Search looks at triggers and expansions."
                        ) {
                            Button("Clear Search") { query = "" }
                                .buttonStyle(.flowSecondary)
                        }
                        .cardSurface()
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Layout.Main.snippetCardMinWidth), spacing: Spacing.m)],
                            alignment: .leading,
                            spacing: Spacing.m
                        ) {
                            ForEach(visible) { snippet in
                                SnippetCard(
                                    snippet: snippet,
                                    uses: uses[snippet.id] ?? 0,
                                    onToggle: { isOn in
                                        var updated = snippet
                                        updated.isEnabled = isOn
                                        model.snippets.update(updated)
                                    },
                                    onEdit: { editing = snippet },
                                    onDelete: { delete(snippet) }
                                )
                            }
                        }
                    }
                }
            }
            .pageLayout()
            // Room for the toast, so the last card's footer can scroll clear of it.
            .padding(.bottom, undoMessage == nil ? 0 : Layout.Main.floatingBarClearance)
        }
        .overlay(alignment: .bottom) {
            UndoToast(message: undoMessage) { model.snippets.undoDeletion() }
        }
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: store.deletion.pending)
        // As in History, leaving the page doesn't make a delete final: it stays undoable for
        // the rest of its window (the store commits it then, or at quit).
        .sheet(isPresented: $isAdding) {
            SnippetEditorSheet(original: nil) { model.snippets.add($0) }
                .environment(model)
        }
        .sheet(item: $editing) { snippet in
            SnippetEditorSheet(original: snippet) { model.snippets.update($0) }
                .environment(model)
        }
    }

    /// Deletes at once, with Undo (and ⌘Z) for `Motion.undoWindow`, as History does.
    private func delete(_ snippet: Snippet) {
        if editing?.id == snippet.id { editing = nil }
        model.snippets.delete(ids: [snippet.id], undoWindow: Motion.undoWindow)
        // VoiceOver hears which snippet went; the toast stays short, as History's does.
        UndoToast.announce("Snippet “\(snippet.trigger)” deleted")
    }

    /// "Snippet deleted", worded like History's "Dictation deleted", while a delete can
    /// still be undone.
    private var undoMessage: String? {
        let store = model.snippets
        let count = store.snippets.filter { store.deletion.isPending($0.id) }.count
        guard count > 0 else { return nil }
        return count == 1 ? "Snippet deleted" : "\(count) snippets deleted"
    }
}

private struct SnippetCard: View {
    let snippet: Snippet
    let uses: Int
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .center, spacing: Spacing.s) {
                // The logo's bars mark what you say, as they do in the app's own mark.
                LogoBars()
                    .fill(Palette.inkTertiary)
                    .frame(width: LogoBars.groupWidth(height: Layout.Main.triggerMark), height: Layout.Main.triggerMark)
                    .accessibilityHidden(true)
                    .opacity(dimming)
                Text("“\(snippet.trigger)”")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .help(snippet.trigger)
                    .opacity(dimming)
                Spacer(minLength: Spacing.s)
                // Hidden visually; VoiceOver names the switch after the snippet it controls.
                Toggle("Snippet “\(snippet.trigger)”", isOn: Binding(get: { snippet.isEnabled }, set: { onToggle($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(snippet.isEnabled ? "Turn off without deleting" : "Turn back on")
            }
            Text(snippet.expansion)
                .font(Typography.transcript)
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(Spacing.transcriptLine)
                .lineLimit(Layout.Main.transcriptLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(snippet.expansion)
                .opacity(dimming)
            Spacer(minLength: 0)
            HStack(spacing: Spacing.xxs) {
                Text(uses == 0 ? "Not used yet" : (uses == 1 ? "Used once" : "Used \(uses) times"))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .opacity(dimming)
                Spacer(minLength: Spacing.s)
                HStack(spacing: Spacing.xxs) {
                    IconButton(symbol: "pencil", label: "Edit") { onEdit() }
                    IconButton(symbol: "trash", label: "Delete") { onDelete() }
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, minHeight: Layout.Main.snippetCardMinHeight, alignment: .topLeading)
        .cardSurface(isHovered: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onEdit() }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { onEdit() }
            Button(snippet.isEnabled ? "Turn Off" : "Turn On", systemImage: "power") { onToggle(!snippet.isEnabled) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
        // The hover buttons are invisible (and so missing from the accessibility tree) most of
        // the time; offer Edit and Delete as VoiceOver actions on the card.
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Edit") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    /// A turned-off snippet dims everything it says, as a dictionary row does; the switch and
    /// the actions stay at full strength.
    private var dimming: Double {
        snippet.isEnabled ? 1 : Interaction.dimmedOpacity
    }
}

/// Add or edit a snippet. Warns when another snippet already uses the trigger.
struct SnippetEditorSheet: View {
    let original: Snippet?
    let onSave: (Snippet) -> Void

    @State private var trigger: String
    @State private var expansion: String
    @FocusState private var expansionFocused: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init(original: Snippet?, onSave: @escaping (Snippet) -> Void) {
        self.original = original
        self.onSave = onSave
        _trigger = State(initialValue: original?.trigger ?? "")
        _expansion = State(initialValue: original?.expansion ?? "")
    }

    private var trimmedTrigger: String { trigger.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hasConflict: Bool {
        model.snippets.hasConflict(trigger: trimmedTrigger, excluding: original?.id)
    }

    /// The pipeline matches triggers word by word, so one made only of punctuation never fires.
    private var triggerHasWords: Bool {
        trimmedTrigger.contains { $0.isLetter || $0.isNumber }
    }

    private var canSave: Bool {
        triggerHasWords && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasConflict
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(original == nil ? "New Snippet" : "Edit Snippet")
                .font(Typography.title)
                .tracking(Tracking.title)
                .foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                LabeledInput(label: "When you say", text: $trigger, prompt: "my calendly link")
                if !trimmedTrigger.isEmpty && !triggerHasWords {
                    problemRow("A trigger needs at least one word you can say.")
                } else if hasConflict {
                    problemRow("Another snippet already uses “\(trimmedTrigger)”. Pick a different phrase.")
                } else {
                    Text("A short phrase you wouldn't say by accident works best.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("It types")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                TextEditor(text: $expansion)
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.s)
                    .frame(height: Layout.Main.expansionEditorHeight)
                    .background(shape.fill(Palette.sunken))
                    .focused($expansionFocused)
                    .overlay(shape.strokeBorder(
                        expansionFocused ? Palette.accent : Palette.hairline,
                        lineWidth: expansionFocused ? Layout.Main.focusRing : Layout.Main.hairline
                    ))
                    .accessibilityLabel("Expansion")
            }

            HStack(spacing: Spacing.s) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.flowSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save") {
                    save()
                    dismiss()
                }
                .buttonStyle(.flowPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.xxl)
        .frame(width: Layout.Main.sheetWidth)
        .background(Palette.canvas)
    }

    /// A message that blocks saving, drawn like the dictionary sheet's so it doesn't read as advice.
    private func problemRow(_ message: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(Palette.danger)
            Text(message)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Typography.callout)
    }

    private func save() {
        if let original {
            var updated = original
            updated.trigger = trimmedTrigger
            updated.expansion = expansion
            onSave(updated)
        } else {
            onSave(Snippet(trigger: trimmedTrigger, expansion: expansion))
        }
    }
}
