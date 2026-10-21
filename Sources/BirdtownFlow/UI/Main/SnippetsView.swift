import MurmurKit
import SwiftUI

/// Snippets: say a trigger phrase, get the expansion typed.
struct SnippetsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var isAdding = false
    @State private var editing: Snippet?
    /// "New Snippet" opened the sheet, so it takes focus back when the sheet closes.
    @State private var addOpenedSheet = false
    @FocusState private var newSnippetFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let store = model.snippets
        let uses = LibraryUsage.snippetCounts(
            snippets: store.snippets, aliases: store.aliases, records: model.history.records)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Snippets waiting out a delete's undo window are hidden.
        let visible = store.visible.filter {
            trimmed.isEmpty || $0.trigger.localizedStandardContains(trimmed) || $0.expansion.localizedStandardContains(trimmed)
                || ($0.link?.localizedStandardContains(trimmed) ?? false)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.Library.blockGap) {
                PageHeader(
                    title: "Snippets",
                    subtitle: "A few spoken words. The whole thing, typed.",
                    symbol: "text.badge.plus",
                    tone: .teal
                ) {
                    Button {
                        openNewSnippet()
                    } label: {
                        Label("New Snippet", systemImage: "plus")
                    }
                    .buttonStyle(.flowPrimary)
                    .focused($newSnippetFocused)
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
                        Button("New Snippet") { openNewSnippet() }
                            .buttonStyle(.flowSecondary)
                    }
                    .dashedPanel()
                } else {
                    searchRow(total: store.visible.count, matching: visible.count, isSearching: !trimmed.isEmpty)
                    if visible.isEmpty {
                        EmptyState(
                            symbol: "magnifyingglass",
                            title: "No snippets match “\(trimmed)”",
                            message: "Search looks at the phrase you say, the text it types and its link. "
                                + "Clear the search to see every snippet."
                        ) {
                            Button("Clear Search") { query = "" }
                                .buttonStyle(.flowSecondary)
                        }
                        .dashedPanel()
                    } else {
                        VStack(alignment: .leading, spacing: Layout.Library.snippetCardGap) {
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
                        if trimmed.isEmpty {
                            tip
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
        .sheet(isPresented: $isAdding, onDismiss: restoreFocusToOpener) {
            SnippetEditorSheet(original: nil, onSave: { model.snippets.add($0) })
                .environment(model)
        }
        .sheet(item: $editing) { snippet in
            SnippetEditorSheet(
                original: snippet,
                onSave: { model.snippets.update($0) },
                onDelete: { delete(snippet) }
            )
            .environment(model)
        }
    }

    private func openNewSnippet() {
        addOpenedSheet = true
        isAdding = true
    }

    /// The system returns focus to the card's own button after Edit; only the page's "New
    /// Snippet" button needs help.
    private func restoreFocusToOpener() {
        guard addOpenedSheet else { return }
        addOpenedSheet = false
        newSnippetFocused = true
    }

    private func searchRow(total: Int, matching: Int, isSearching: Bool) -> some View {
        HStack(spacing: Spacing.xl) {
            SearchField(text: $query, prompt: "Find a snippet")
                .frame(width: Layout.Main.searchFieldWidth)
            Spacer(minLength: Spacing.l)
            let noun = total == 1 ? "snippet" : "snippets"
            Text(isSearching ? "\(matching) of \(total) \(noun)" : "\(total) \(noun)")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
                .monospacedDigit()
        }
    }

    /// A nudge under the list, in the handoff's dashed panel.
    private var tip: some View {
        HStack(spacing: Layout.Library.tipGap) {
            Image(systemName: "text.badge.plus")
                .font(Typography.pageSymbol)
                .foregroundStyle(Palette.teal)
                .frame(width: Layout.Library.tipIcon, height: Layout.Library.tipIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Save the things you say again and again.")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                Text("Meeting links, your address, a sign-off. Give each one a phrase that feels natural to say.")
                    .font(Typography.bodyLarge)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Layout.Library.tipInsetVertical)
        .padding(.horizontal, Layout.Library.tipInsetHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashedPanel()
        .accessibilityElement(children: .combine)
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

/// One snippet in two parts: what you say on a teal wash, what Birdtown Flow types beside it.
private struct SnippetCard: View {
    let snippet: Snippet
    let uses: Int
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            triggerPane
                .frame(width: Layout.Library.snippetTriggerWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.tealSoft)
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: Layout.Main.hairline)
            expansionPane
        }
        .cardSurface()
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { onEdit() }
            Button(snippet.isEnabled ? "Turn Off" : "Turn On", systemImage: "power") { onToggle(!snippet.isEnabled) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
        // Delete lives in the context menu and the edit sheet; offer it to VoiceOver here too.
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Edit") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    /// What you say, and how often you have.
    private var triggerPane: some View {
        VStack(alignment: .leading, spacing: Layout.Library.snippetGap) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "mic")
                    .accessibilityHidden(true)
                Text("When you say")
                Spacer(minLength: Spacing.s)
                // A turned-off snippet is also dimmed, but the dimming isn't the only cue.
                if !snippet.isEnabled {
                    Badge(text: "Off")
                }
            }
            .font(Typography.callout)
            .foregroundStyle(Palette.teal)
            Text("“\(snippet.trigger)”")
                .font(Typography.snippetTrigger)
                .tracking(Tracking.snippetTrigger)
                .foregroundStyle(snippet.isEnabled ? Palette.ink : Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .help(snippet.trigger)
            Spacer(minLength: Spacing.s)
            Text(uses == 0 ? "Not used yet" : (uses == 1 ? "Used once" : "Used \(uses) times"))
                .font(Typography.callout)
                .foregroundStyle(Palette.teal)
        }
        .padding(Layout.Library.snippetInset)
    }

    /// What Birdtown Flow types, with Edit and the switch under it.
    private var expansionPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Flow types")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
            let link = snippet.linked
            expansionText
                .font(Typography.transcript)
                .foregroundStyle(snippet.isEnabled ? Palette.ink : Palette.inkTertiary)
                .lineSpacing(Spacing.transcriptLine)
                .lineLimit(Layout.Library.expansionLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.m)
                .help(snippet.expansion)
            if let link {
                Label(link.url, systemImage: "link")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, Spacing.xs)
                    .help(link.url)
                    .accessibilityLabel("Links to \(link.url)")
            }
            Spacer(minLength: Layout.Library.snippetFooterTop)
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: Layout.Main.hairline)
            HStack(spacing: Spacing.l) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit snippet", systemImage: "pencil")
                }
                .buttonStyle(EditLinkButtonStyle())
                Spacer(minLength: Spacing.s)
                // Hidden visually; VoiceOver names the switch after the snippet it controls.
                Toggle("Snippet “\(snippet.trigger)”", isOn: Binding(get: { snippet.isEnabled }, set: { onToggle($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(snippet.isEnabled ? "Turn off without deleting" : "Turn back on")
            }
            .padding(.top, Layout.Library.snippetFooterInset)
        }
        .padding(Layout.Library.snippetInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The expansion with its linked words reading as a link: Signal blue, underlined, with the
    /// address under the card's text. Only those words when the snippet links part of it.
    private var expansionText: Text {
        let expansion = snippet.expansion
        guard let range = snippet.linkedRange else { return Text(expansion) }
        let linked = Text(expansion[range])
            .foregroundStyle(snippet.isEnabled ? Palette.accentInk : Palette.inkTertiary)
            .underline()
        let before = String(expansion[..<range.lowerBound])
        let after = String(expansion[range.upperBound...])
        return Text("\(before)\(linked)\(after)")
    }
}

/// "Edit snippet": a Signal blue text link that underlines on hover and dims on press.
private struct EditLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EditLinkBody(configuration: configuration)
    }
}

private struct EditLinkBody: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(Typography.caption)
            .foregroundStyle(Palette.accentInk)
            .underline(isHovered)
            .opacity(configuration.isPressed ? Interaction.dimmedOpacity : 1)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
            // The system's focus ring, shaped to the link.
            .flowFocusRing(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }
}

/// Add or edit a snippet. Warns when another snippet already uses the trigger.
struct SnippetEditorSheet: View {
    let original: Snippet?
    let onSave: (Snippet) -> Void
    /// Offered when editing: removes the snippet, with Undo on the page behind the sheet.
    let onDelete: (() -> Void)?

    @State private var trigger: String
    @State private var expansion: String
    @State private var link: String
    @State private var linkText: String
    @FocusState private var expansionFocused: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init(original: Snippet?, onSave: @escaping (Snippet) -> Void, onDelete: (() -> Void)? = nil) {
        self.original = original
        self.onSave = onSave
        self.onDelete = onDelete
        _trigger = State(initialValue: original?.trigger ?? "")
        _expansion = State(initialValue: original?.expansion ?? "")
        _link = State(initialValue: original?.link ?? "")
        _linkText = State(initialValue: original?.linkText ?? "")
    }

    private var trimmedTrigger: String { trigger.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hasConflict: Bool {
        model.snippets.hasConflict(trigger: trimmedTrigger, excluding: original?.id)
    }

    /// The pipeline matches triggers word by word, so one made only of punctuation never fires.
    private var triggerHasWords: Bool {
        trimmedTrigger.contains { $0.isLetter || $0.isNumber }
    }

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The address to save: `nil` for no link, and also for one that isn't an address.
    private var normalizedLink: String? { SnippetLink.normalizedURL(trimmedLink) }

    private var linkIsInvalid: Bool { !trimmedLink.isEmpty && normalizedLink == nil }

    private var trimmedLinkText: String { linkText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "Words to link" shows once there's an address to link, or if words were saved before.
    private var showsLinkText: Bool { !trimmedLink.isEmpty || !trimmedLinkText.isEmpty }

    /// Words to link that the expansion doesn't contain: saving would link something else.
    private var linkTextIsMissing: Bool {
        normalizedLink != nil && !trimmedLinkText.isEmpty && Snippet.range(of: trimmedLinkText, in: expansion) == nil
    }

    /// The words to save: `nil` links the whole expansion, and there's nothing to link without an address.
    private var savedLinkText: String? {
        normalizedLink == nil || trimmedLinkText.isEmpty ? nil : trimmedLinkText
    }

    private var linkTextHint: String {
        trimmedLinkText.isEmpty
            ? "Leave it empty to link all of the text, or pick a few words from it to link only those."
            : "Only “\(trimmedLinkText)” becomes the link. The rest is typed as plain text."
    }

    private var canSave: Bool {
        triggerHasWords && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasConflict
            && !linkIsInvalid && !linkTextIsMissing
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(original == nil ? "New Snippet" : "Edit Snippet")
                .font(Typography.sectionTitle)
                .tracking(Tracking.title)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                LabeledInput(label: "When you say", text: $trigger, prompt: "my calendly link", autofocus: true)
                if !trimmedTrigger.isEmpty && !triggerHasWords {
                    problemRow("A trigger needs at least one word you can say.")
                } else if hasConflict {
                    problemRow("Another snippet already uses “\(trimmedTrigger)”. Pick a different phrase.")
                } else {
                    Text("A short phrase you wouldn't say by accident works best.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("It types")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                // Return adds a line here, so Enter submits from the trigger field only.
                TextEditor(text: $expansion)
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.s)
                    .frame(height: Layout.Main.expansionEditorHeight)
                    .background(shape.fill(Palette.surface))
                    .focused($expansionFocused)
                    .overlay(shape.strokeBorder(Palette.hairlineStrong, lineWidth: Layout.Main.hairline))
                    .flowFocusRing(shape, drawn: expansionFocused)
                    .accessibilityLabel("Expansion")
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                LabeledInput(label: "Link it to (optional)", text: $link, prompt: "https://calendar.app.google/…")
                if linkIsInvalid {
                    problemRow("That isn't a web address. Paste the whole link, starting with https://.")
                } else {
                    Text(trimmedLink.isEmpty
                        ? "Add an address and the text above becomes a link to it, like ⌘K in a document."
                        : "Where links can't show, like Messages, the address goes in brackets after the linked words.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsLinkText {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    LabeledInput(label: "Words to link (optional)", text: $linkText, prompt: "my calendar")
                    if linkTextIsMissing {
                        problemRow(
                            "“\(trimmedLinkText)” isn't in the text above. Copy the words from there.")
                    } else {
                        Text(linkTextHint)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: Spacing.s) {
                if original != nil, let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .buttonStyle(.flowSecondary)
                }
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
        .background(Palette.surface)
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
            updated.link = normalizedLink
            updated.linkText = savedLinkText
            onSave(updated)
        } else {
            onSave(Snippet(
                trigger: trimmedTrigger, expansion: expansion, link: normalizedLink, linkText: savedLinkText))
        }
    }
}
