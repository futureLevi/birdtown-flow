import AppKit
import MurmurDictionary
import MurmurKit
import SwiftUI

/// The dictionary: replacements ("hear X, write Y") and vocabulary, editable here or as a
/// plain text file that reloads live.
struct DictionaryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var isAdding = false
    @State private var editing: DictionaryEntry?

    var body: some View {
        let store = model.dictionary
        let entries = store.filtered(by: query)
        let fired = Self.firedCounts(in: model.history.records)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                PageHeader(
                    title: "Dictionary",
                    subtitle: "Teach Murmur the names, products and jargon you use."
                ) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add Entry", systemImage: "plus")
                    }
                    .buttonStyle(.murmurPrimary)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Add a word or a replacement (⌘N)")
                }

                if store.entries.isEmpty {
                    EmptyState(
                        symbol: "character.book.closed",
                        title: "Start with a word Murmur gets wrong",
                        message: "Add a name, a product or a bit of jargon, or tell it that when it hears "
                            + "“cloud code” you mean “Claude Code”."
                    ) {
                        Button("Add Entry") { isAdding = true }
                            .buttonStyle(.murmurSecondary)
                    }
                    .cardSurface()
                } else {
                    SearchField(text: $query, prompt: "Search dictionary")
                        .frame(maxWidth: Layout.Main.searchFieldWidth)
                    if entries.isEmpty {
                        EmptyState(
                            symbol: "magnifyingglass",
                            title: "No entries match “\(query)”",
                            message: "Search looks at both sides of a replacement."
                        )
                    } else {
                        group(
                            title: "Replacements",
                            explainer: "When Murmur hears the phrase on the left, it writes the one on the right.",
                            entries: entries.filter { $0.kind == .correction },
                            fired: fired
                        )
                        group(
                            title: "Vocabulary",
                            explainer: "Words Murmur listens for, spelled exactly the way you want them.",
                            entries: entries.filter { $0.kind == .term },
                            fired: fired
                        )
                    }
                }

                fileNote
            }
            .pageLayout()
        }
        .sheet(isPresented: $isAdding) {
            DictionaryEditorSheet(original: nil) { model.dictionary.add($0) }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditorSheet(original: entry) { model.dictionary.update($0) }
        }
    }

    @ViewBuilder
    private func group(title: String, explainer: String, entries: [DictionaryEntry], fired: [String: Int]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SectionHeader(title, detail: "\(entries.count)")
                    Text(explainer)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider(leadingInset: Spacing.l) }
                        DictionaryRow(
                            entry: entry,
                            firedCount: entry.kind == .correction ? fired[entry.write.lowercased()] ?? 0 : 0,
                            onToggle: { isOn in
                                var updated = entry
                                updated.isEnabled = isOn
                                model.dictionary.update(updated)
                            },
                            onEdit: { editing = entry },
                            onDelete: { model.dictionary.delete(entry) }
                        )
                    }
                }
                .cardSurface()
            }
        }
    }

    private var fileNote: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "doc.plaintext")
                .foregroundStyle(Palette.inkTertiary)
            Text("Prefer a text editor? The dictionary is a plain file, and edits show up here instantly.")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: Spacing.s)
            Button("Open dictionary.txt") { NSWorkspace.shared.open(DictionaryStore.fileURL) }
                .buttonStyle(.murmurGhost)
                .controlSize(.small)
                .help(DictionaryStore.fileURL.path)
                .disabled(!FileManager.default.fileExists(atPath: DictionaryStore.fileURL.path))
        }
    }

    /// How often each replacement has fired, keyed by what it writes (lowercased).
    static func firedCounts(in records: [HistoryRecord]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for record in records {
            for correction in record.corrections {
                counts[correction.to.lowercased(), default: 0] += correction.count
            }
        }
        return counts
    }
}

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let firedCount: Int
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let warnings = DictionaryWarning.check(entry)
        HStack(alignment: .center, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.s) {
                    if entry.kind == .correction {
                        Text(entry.hear)
                            .font(Typography.body)
                            .foregroundStyle(Palette.inkSecondary)
                        Image(systemName: "arrow.right")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                            .accessibilityLabel("becomes")
                    }
                    Text(entry.write)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                }
                ForEach(warnings) { warning in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warning)
                        Text(warning.message)
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Typography.caption)
                }
            }
            .opacity(entry.isEnabled ? 1 : Interaction.dimmedOpacity)

            Spacer(minLength: Spacing.m)

            if firedCount > 0 {
                Text("Fixed \(firedCount)×")
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkTertiary)
                    .help("Times this replacement has corrected a dictation in your history")
            }
            HStack(spacing: Spacing.xxs) {
                IconButton(symbol: "pencil", label: "Edit") { onEdit() }
                IconButton(symbol: "trash", label: "Delete") { onDelete() }
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            Toggle("Enabled", isOn: Binding(get: { entry.isEnabled }, set: { onToggle($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(entry.isEnabled ? "Turn off without deleting" : "Turn back on")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .frame(minHeight: Layout.rowMinHeight)
        .background(isHovered ? Palette.surfaceHover : Palette.surface)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onEdit() }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { onEdit() }
            Button(entry.isEnabled ? "Turn Off" : "Turn On", systemImage: "power") { onToggle(!entry.isEnabled) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
    }
}

/// Add or edit one dictionary entry, with false-positive warnings shown live as you type.
struct DictionaryEditorSheet: View {
    let original: DictionaryEntry?
    /// The dictation this entry came from, offered as context and quick-fill suggestions.
    let context: String?
    let onSave: (DictionaryEntry) -> Void

    @State private var kind: DictionaryEntry.Kind
    @State private var write: String
    @State private var hear: String
    @Environment(\.dismiss) private var dismiss

    init(
        original: DictionaryEntry?,
        kind: DictionaryEntry.Kind = .term,
        context: String? = nil,
        onSave: @escaping (DictionaryEntry) -> Void
    ) {
        self.original = original
        self.context = context
        self.onSave = onSave
        _kind = State(initialValue: original?.kind ?? kind)
        _write = State(initialValue: original?.write ?? "")
        _hear = State(initialValue: original?.hear ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: original?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: original?.isEnabled ?? true
        )
    }

    private var canSave: Bool {
        !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(original == nil ? "Add to Dictionary" : "Edit Entry")
                .font(Typography.title)
                .tracking(Tracking.title)
                .foregroundStyle(Palette.ink)

            Picker("Kind", selection: $kind) {
                Text("Vocabulary").tag(DictionaryEntry.Kind.term)
                Text("Replacement").tag(DictionaryEntry.Kind.correction)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(kind == .term
                 ? "A word Murmur should expect, spelled exactly how you want it written."
                 : "When Murmur hears the first phrase, it writes the second instead.")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)

            if let context, !context.isEmpty {
                contextBlock(context)
            }

            if kind == .correction {
                LabeledInput(label: "When Murmur hears", text: $hear, prompt: "cloud code")
            }
            LabeledInput(
                label: kind == .term ? "Word or phrase" : "Write",
                text: $write,
                prompt: kind == .term ? "Anthropic" : "Claude Code"
            )

            ForEach(DictionaryWarning.check(draft)) { warning in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.warning)
                    Text(warning.message)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Typography.callout)
            }

            HStack(spacing: Spacing.s) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.murmurSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.murmurPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.xxl)
        .frame(width: Layout.Main.sheetWidth)
        .background(Palette.canvas)
    }

    private func contextBlock(_ context: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(context)
                .font(Typography.transcript)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(Layout.Main.transcriptLines)
                .textSelection(.enabled)
            let suggestions = Self.suggestions(from: context)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(suggestions, id: \.self) { word in
                            FilterChip(title: word, isSelected: false) {
                                if kind == .correction && hear.isEmpty { hear = word } else { write = word }
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Palette.sunken))
    }

    /// Words in the dictation most likely to be names or jargon: capitalised mid-sentence,
    /// or mixing letters with digits or inner capitals.
    static func suggestions(from text: String, limit: Int = 6) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let sentenceEnders: Set<Character> = [".", "!", "?", "\n"]
        var previous: Character = "."
        for raw in text.split(separator: " ", omittingEmptySubsequences: true) {
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            defer { previous = raw.last ?? previous }
            guard word.count > 2, let first = word.first else { continue }
            let startsSentence = sentenceEnders.contains(previous)
            let innerCapital = word.dropFirst().contains { $0.isUppercase }
            let hasDigit = word.contains { $0.isNumber }
            let isName = first.isUppercase && !startsSentence
            guard isName || innerCapital || hasDigit else { continue }
            if seen.insert(word.lowercased()).inserted {
                result.append(word)
            }
            if result.count == limit { break }
        }
        return result
    }
}
