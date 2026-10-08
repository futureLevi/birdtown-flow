import AppKit
import MurmurKit
import SwiftUI

/// The Lab: named polish configurations (provider, model, effort, instructions), tried on the
/// same text and compared under one header per text, then handed the writing styles they
/// should polish. Styles without one keep following Settings, so nothing changes for everyday
/// dictation until you say so.
struct LabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deleting: PolishConfiguration?

    var body: some View {
        let bench = model.bench
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    PageHeader(
                        title: "Lab",
                        subtitle: "Tune polish configurations on real dictations, then pick the styles each one polishes. "
                            + "Styles without one follow Settings."
                    ) {
                        Button {
                            bench.addNew()
                        } label: {
                            Label("New Configuration", systemImage: "plus")
                        }
                        .buttonStyle(.flowSecondary)
                        .keyboardShortcut("n", modifiers: .command)
                        .help("Start a new configuration (⌘N)")
                    }

                    if model.settings.polishProvider == .off {
                        Banner(
                            symbol: "sparkles",
                            title: "AI polish is off",
                            message: "Configurations still run here, but dictation won't use them until AI polish is on.",
                            tone: .info
                        ) {
                            SettingsLink {
                                Text("Open Settings")
                            }
                            .buttonStyle(.flowSecondary)
                            .controlSize(.small)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionHeader("Configurations", detail: "\(model.lab.configurations.count)")
                        if model.lab.configurations.isEmpty {
                            // No list to pick from, so no empty column beside the message.
                            EmptyState(
                                symbol: "flask",
                                title: "No configurations yet",
                                message: "Start one to try polish settings on real dictations."
                            ) {
                                Button("New Configuration") { bench.addNew() }
                                    .buttonStyle(.flowPrimary)
                            }
                            .cardSurface()
                        } else {
                            HStack(alignment: .top, spacing: Spacing.m) {
                                LabConfigurationList(onDelete: { deleting = $0 }) { id in
                                    // No anchor: scroll only as far as it takes to bring the row into view.
                                    withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
                                        proxy.scrollTo(LabRowAnchor(id: id))
                                    }
                                }
                                .frame(width: Layout.Lab.listWidth)
                                if let selected = bench.selected {
                                    LabEditor(configuration: selected, onDelete: { deleting = $0 }, onApplied: { applied() })
                                        // A fresh editor per configuration: no focus or scroll carried over.
                                        .id(selected.id)
                                } else {
                                    EmptyState(
                                        symbol: "flask",
                                        title: "No configuration open",
                                        message: "Pick a configuration on the left."
                                    )
                                    .cardSurface()
                                }
                            }
                        }
                    }

                    LabTestCard()

                    LabResults()
                }
                .pageLayout()
            }
        }
        .confirmationDialog(
            "Delete “\(deleting?.displayName ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { configuration in
            Button("Delete", role: .destructive) {
                bench.delete(configuration.id)
                applied()
            }
            Button("Cancel", role: .cancel) {}
        } message: { configuration in
            Text(model.lab.styles(for: configuration.id).isEmpty
                 ? "This can't be undone."
                 : "The styles it polishes go back to following Settings. This can't be undone.")
        }
        .onAppear { if isLive { bench.schedulePrewarm() } }
        .onChange(of: bench.selectedID) { if isLive { bench.schedulePrewarm() } }
        .onChange(of: bench.sampleStyle) { if isLive { bench.schedulePrewarm() } }
        .onChange(of: bench.sampleCategory) { if isLive { bench.schedulePrewarm() } }
        // Back to a session for dictation, now that the Lab's tests are done.
        .onDisappear { if isLive { model.controller.polishSettingsChanged() } }
    }

    /// Snapshots render with a fixed status and must not start anything.
    private var isLive: Bool { preview.status == nil }

    /// After a save, an assignment or a deletion, keep a session ready for the next test.
    /// Dictation needs nothing here: it starts its own session as you begin talking, and
    /// leaving the Lab hands the waiting session back to it.
    private func applied() {
        guard isLive else { return }
        model.bench.schedulePrewarm()
    }
}

// MARK: - Configurations

/// Behaves like a Mail list once it has focus (a click on a row, or Tab): ↑/↓ open the
/// configuration above or below, Delete asks to delete the open one, and the open row wears
/// the Signal blue focus ring. ⌘D (Duplicate) lives on the editor's button.
private struct LabConfigurationList: View {
    let onDelete: (PolishConfiguration) -> Void
    /// Scrolls the page so a row reached from the keyboard is on screen.
    let reveal: (UUID) -> Void
    @Environment(AppModel.self) private var model
    @FocusState private var listFocused: Bool

    var body: some View {
        let bench = model.bench
        let order = model.lab.configurations.map(\.id)
        VStack(spacing: Spacing.s) {
            ForEach(model.lab.configurations) { saved in
                LabConfigurationRow(
                    configuration: bench.version(of: saved.id) ?? saved,
                    styles: model.lab.styles(for: saved.id),
                    isSelected: bench.selectedID == saved.id,
                    hasFocusRing: listFocused && bench.selectedID == saved.id,
                    hasUnsavedChanges: bench.hasUnsavedChanges(saved.id)
                ) {
                    bench.selectedID = saved.id
                    // So ↑/↓ and Delete work straight after a click, as in any Mac list.
                    listFocused = true
                }
                .id(LabRowAnchor(id: saved.id))
                .contextMenu {
                    Button("Duplicate") { bench.duplicate(saved.id) }
                    Divider()
                    Button("Delete…", role: .destructive) { onDelete(saved) }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            move(press.key == .upArrow ? -1 : 1, order: order)
        }
        .onDeleteCommand {
            guard let id = bench.selectedID, let saved = model.lab.configuration(id: id) else { return }
            onDelete(saved)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Configurations")
    }

    private func move(_ step: Int, order: [UUID]) -> KeyPress.Result {
        let bench = model.bench
        guard let target = PolishLabNavigation.neighbor(of: bench.selectedID, step: step, in: order) else {
            return .ignored
        }
        bench.selectedID = target
        reveal(target)
        return .handled
    }
}

/// A list row's scroll target, apart from the editor's `.id`, which is the same configuration id.
private struct LabRowAnchor: Hashable {
    let id: UUID
}

private struct LabConfigurationRow: View {
    let configuration: PolishConfiguration
    let styles: Set<WritingStyle>
    let isSelected: Bool
    /// The list has keyboard focus and this is the open row.
    let hasFocusRing: Bool
    let hasUnsavedChanges: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text(configuration.displayName)
                        .font(Typography.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.xs)
                    if hasUnsavedChanges {
                        StatusDot(color: Palette.warning)
                            .help("Unsaved changes")
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    if configuration.usesModel, !configuration.model.isEmpty {
                        Text(configuration.model)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(configuration.providerAndEffort)
                        .foregroundStyle(Palette.inkTertiary)
                        .lineLimit(1)
                }
                .font(Typography.caption)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Image(systemName: styles.isEmpty ? "circle.dashed" : "checkmark.circle.fill")
                        .foregroundStyle(styles.isEmpty ? Palette.inkTertiary : Palette.success)
                    Text(usedFor)
                        .foregroundStyle(styles.isEmpty ? Palette.inkTertiary : Palette.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Typography.caption)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The list takes focus as a whole; a row never does on its own.
        .focusable(false)
        .cardSurface(isSelected: isSelected, isHovered: isHovered && !isSelected, radius: Radius.m)
        .flowFocusRing(RoundedRectangle(cornerRadius: Radius.m, style: .continuous), drawn: hasFocusRing)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(hasUnsavedChanges ? "Has unsaved changes" : "")
    }

    private var usedFor: String {
        let names = WritingStyle.allCases.filter(styles.contains).map(\.title)
        return names.isEmpty ? "Not used yet" : "Used for " + ListFormatter.localizedString(byJoining: names)
    }
}

// MARK: - Editor

private struct LabEditor: View {
    /// The version on screen: unsaved edits included.
    let configuration: PolishConfiguration
    let onDelete: (PolishConfiguration) -> Void
    let onApplied: () -> Void

    @Environment(AppModel.self) private var model
    @FocusState private var instructionsFocused: Bool

    var body: some View {
        let bench = model.bench
        let id = configuration.id
        let saved = model.lab.configuration(id: id)
        let isDirty = bench.hasUnsavedChanges(id)
        Card(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .bottom, spacing: Spacing.m) {
                    LabField(label: "Name") {
                        LabTextInput("Name", text: binding(\.name), prompt: "Filler words v2")
                    }
                    HStack(spacing: Spacing.xxs) {
                        IconButton(symbol: "plus.square.on.square", label: "Duplicate") { bench.duplicate(id) }
                            .keyboardShortcut("d", modifiers: .command)
                        IconButton(symbol: "trash", label: "Delete…") { onDelete(saved ?? configuration) }
                    }
                    .padding(.bottom, Spacing.xxs)
                }
                LabField(label: "Notes") {
                    LabTextInput("Notes", text: binding(\.notes), prompt: "What this version tries")
                }

                HStack(alignment: .top, spacing: Spacing.l) {
                    LabField(label: "Provider") {
                        LabPicker(
                            label: "Provider",
                            options: PolishConfiguration.providers,
                            title: PolishConfiguration.providerTitle,
                            selection: Binding(get: { configuration.provider }, set: { switchProvider($0) })
                        )
                        .frame(width: Layout.Lab.providerWidth)
                    }
                    if configuration.usesModel {
                        LabField(label: "Model") { modelField }
                    }
                }
                if configuration.usesEffort {
                    LabField(label: "Effort") {
                        Picker("Effort", selection: binding(\.effort)) {
                            ForEach(PolishEffort.allCases) { effort in
                                Text(effort.shortTitle).tag(effort)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                instructions

                footer(saved: saved, isDirty: isDirty)

                // Outside the draft: a chip applies as soon as it's clicked, so it sits apart
                // from the fields that wait for Save.
                Divider()

                usedFor(isDirty: isDirty)
            }
        }
    }

    // MARK: Fields

    /// Edits go to the bench as a draft; nothing is saved until Save.
    private func binding<Value>(_ keyPath: WritableKeyPath<PolishConfiguration, Value>) -> Binding<Value> {
        let bench = model.bench
        let fallback = configuration
        return Binding(
            get: { (bench.version(of: fallback.id) ?? fallback)[keyPath: keyPath] },
            set: { value in
                var edited = bench.version(of: fallback.id) ?? fallback
                edited[keyPath: keyPath] = value
                bench.edit(edited)
            }
        )
    }

    /// A Claude model name means nothing to an OpenAI endpoint and the reverse, so switching
    /// between them starts from that provider's usual model.
    private func switchProvider(_ provider: PolishProvider) {
        var edited = model.bench.version(of: configuration.id) ?? configuration
        guard edited.provider != provider else { return }
        let claude: Set<PolishProvider> = [.claudeCode, .anthropic]
        let keepsModel = claude.contains(edited.provider) && claude.contains(provider) && !edited.model.isEmpty
        edited.provider = provider
        if !keepsModel {
            let fromSettings = model.settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.model = provider == .openAICompatible && !fromSettings.isEmpty
                ? fromSettings : PolishConfiguration.defaultModel(for: provider)
        }
        model.bench.edit(edited)
    }

    private var modelField: some View {
        let suggestions = PolishConfiguration.suggestedModels(for: configuration.provider)
        let model = binding(\.model)
        return LabTextInput(
            "Model", text: model, prompt: PolishConfiguration.defaultModel(for: configuration.provider)
        ) {
            // Inside the well, drawn like LabPicker's chevron, so the column's right edge lines up.
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { name in
                        Button(name) { model.wrappedValue = name }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Suggested models")
                .help("Choose a suggested model")
            }
        }
    }

    // MARK: Styles

    private func usedFor(isDirty: Bool) -> some View {
        let lab = model.lab
        let id = configuration.id
        let assigned = lab.styles(for: id)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Use for · applies right away")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkSecondary)
            HStack(spacing: Spacing.s) {
                ForEach(WritingStyle.allCases) { style in
                    let isOn = assigned.contains(style)
                    FilterChip(title: style.title, symbol: isOn ? "checkmark" : nil, isSelected: isOn) {
                        var styles = assigned
                        if isOn { styles.remove(style) } else { styles.insert(style) }
                        lab.setStyles(styles, for: id)
                        onApplied()
                    }
                    .help(chipHelp(for: style, isOn: isOn))
                }
            }
            Text(styleExplanation(assigned: assigned, isDirty: isDirty))
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Which configuration owns a style is on each chip's tooltip, so this stays one line.
    private func styleExplanation(assigned: Set<WritingStyle>, isDirty: Bool) -> String {
        var parts = ["Styles without a configuration follow Settings."]
        if isDirty, !assigned.isEmpty { parts.append("Until you save, they use the saved version.") }
        return parts.joined(separator: " ")
    }

    private func chipHelp(for style: WritingStyle, isOn: Bool) -> String {
        if isOn { return "Stop using this for \(style.title) dictations" }
        if let owner = model.lab.configuration(for: style), owner.id != configuration.id {
            return "Used by “\(owner.displayName)”. Choosing it here moves it."
        }
        return "Polish \(style.title) dictations with this"
    }

    // MARK: Instructions

    private var instructions: some View {
        let text = binding(\.instructions)
        let characters = configuration.instructions.count
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("Instructions")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                Text("\(characters.formatted()) characters, about \((characters / 4).formatted()) tokens")
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkTertiary)
                    .help("Every token of instructions is time the speaker waits.")
                Spacer(minLength: Spacing.s)
                Menu("Start from") {
                    Button("Built-in: filler words only") { text.wrappedValue = PolishPrompt.fillerWordsTemplate }
                    Button("Built-in: full polish") { text.wrappedValue = PolishPrompt.fullTemplate }
                }
                .menuStyle(.borderlessButton)
                .font(Typography.caption)
                .fixedSize()
                .help("Replace the instructions with one of the app's own prompts")
            }
            TextEditor(text: text)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(Spacing.s)
                .frame(height: Layout.Lab.instructionsHeight)
                .focused($instructionsFocused)
                .labWell(isFocused: instructionsFocused)
                .accessibilityLabel("Instructions")
            HStack(spacing: Spacing.xs) {
                ForEach(PolishPlaceholder.allCases) { placeholder in
                    Text(placeholder.token)
                        .font(Typography.caption.monospaced())
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xxs)
                        .background(Capsule().fill(Palette.sunken))
                        .help(placeholder.detail)
                        .textSelection(.enabled)
                }
                Text("are filled in for each dictation.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    // MARK: Footer

    private func footer(saved: PolishConfiguration?, isDirty: Bool) -> some View {
        let bench = model.bench
        let id = configuration.id
        return HStack(spacing: Spacing.s) {
            if isDirty {
                HStack(spacing: Spacing.xs) {
                    StatusDot(color: Palette.warning)
                    Text("Unsaved changes")
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.inkSecondary)
            } else if let saved {
                Text("Saved \(saved.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            Spacer(minLength: Spacing.s)
            if isDirty {
                Button("Revert") { bench.revert(id) }
                    .buttonStyle(.flowGhost)
                    .help("Go back to the saved version")
                Button("Save as Copy") {
                    bench.saveAsCopy(id)
                    onApplied()
                }
                .buttonStyle(.flowSecondary)
                .help("Keep the saved version as it is and save these changes under a new name")
                // Only while there's something to save; clean, the footer just says when it was.
                Button("Save") {
                    bench.save(id)
                    onApplied()
                }
                .buttonStyle(.flowPrimary)
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")
            }
        }
    }
}

// MARK: - Test

private struct LabTestCard: View {
    @Environment(AppModel.self) private var model
    @FocusState private var sampleFocused: Bool

    var body: some View {
        @Bindable var bench = model.bench
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader("Test")
            Card(padding: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text("Text, as the speech engine heard it")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer(minLength: Spacing.s)
                        LabRecentMenu()
                    }
                    TextEditor(text: $bench.sample)
                        .font(Typography.transcript)
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .padding(Spacing.s)
                        .frame(height: Layout.Lab.sampleHeight)
                        .focused($sampleFocused)
                        .labWell(isFocused: sampleFocused)
                        .accessibilityLabel("Text to polish")
                    HStack(spacing: Spacing.s) {
                        Text("Dictated as")
                        LabPicker(label: "Style", options: WritingStyle.allCases, title: \.title,
                                  selection: $bench.sampleStyle)
                            .frame(width: Layout.Lab.styleWidth)
                        Text("into")
                        LabPicker(label: "Kind of app", options: AppCategory.allCases, title: \.title,
                                  selection: $bench.sampleCategory)
                            .frame(width: Layout.Lab.categoryWidth)
                        LabTextInput("App", text: appName, prompt: "App name")
                            .frame(width: Layout.Lab.appFieldWidth)
                        Spacer(minLength: 0)
                    }
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)

                    HStack(spacing: Spacing.s) {
                        if bench.isRunning {
                            ProgressView().controlSize(.small)
                            Text(runningLabel)
                                .font(Typography.callout)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                            Button("Stop") { bench.cancel() }
                                .buttonStyle(.flowGhost)
                                .controlSize(.small)
                        } else {
                            Text("Runs like a dictation: Birdtown Flow's own cleanup, polish, then your style and dictionary.")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Spacing.s)
                        Button("Run All") { bench.runAll() }
                            .buttonStyle(.flowSecondary)
                            .disabled(!bench.canRun || model.lab.configurations.count < 2)
                            .help(runAllHelp)
                        Button {
                            if let id = bench.selectedID { bench.run(id) }
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(.flowPrimary)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!bench.canRun || bench.selected == nil)
                        .help(runHelp)
                    }
                }
            }
        }
    }

    private var appName: Binding<String> {
        let bench = model.bench
        return Binding(
            get: { bench.sampleAppName ?? "" },
            set: { bench.sampleAppName = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        )
    }

    private var sampleIsEmpty: Bool {
        model.bench.sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Says why Run All is off when it is, rather than promising what it won't do.
    private var runAllHelp: String {
        if model.lab.configurations.count < 2 { return "Add a second configuration to compare" }
        if sampleIsEmpty { return "Type or pick some text to test" }
        return "Run every configuration on this text, one after another"
    }

    private var runHelp: String {
        guard let selected = model.bench.selected else { return "Open a configuration to run it" }
        if sampleIsEmpty { return "Type or pick some text to test" }
        return "Run “\(selected.displayName)” on this text (⌘↩)"
    }

    private var runningLabel: String {
        let bench = model.bench
        guard let id = bench.runningID, let run = bench.runs.first(where: { $0.id == id }) else { return "Running…" }
        return "Running “\(run.configuration.displayName)”…"
    }
}

/// Fills the test text from a recent dictation. Its own view so typing in the test text,
/// which re-runs `LabTestCard`, doesn't go through history again.
private struct LabRecentMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bench = model.bench
        let recent = bench.recentDictations(from: model.history)
        Menu {
            if recent.isEmpty {
                Text("No dictations yet")
            }
            ForEach(recent) { record in
                Button(Self.menuTitle(for: record)) { bench.useDictation(record) }
            }
            Divider()
            Button("The sample text") { bench.sample = LabBench.defaultSample }
        } label: {
            Label("Use a recent dictation", systemImage: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .font(Typography.caption)
        .fixedSize()
    }

    private static func menuTitle(for record: HistoryRecord) -> String {
        let excerpt = PolishLabResults.excerpt(record.rawText, maxWords: 9)
        let app = record.context?.appName ?? record.context?.category.title ?? "Dictation"
        return "\(app): \(excerpt)"
    }
}

// MARK: - Results

private struct LabResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bench = model.bench
        if !bench.runs.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Results", detail: "\(bench.runs.count)") {
                    Button("Clear") { bench.clearResults() }
                        .buttonStyle(.flowGhost)
                        .controlSize(.small)
                        .disabled(bench.isRunning)
                }
                // Runs on the same text, style and app sit under one header naming the text, so a
                // Run All batch reads as one comparison and older tests stay apart from it.
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    ForEach(LabRunGroup.groups(bench.runs)) { group in
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            LabRunGroupHeader(group: group)
                            ForEach(group.runs) { run in
                                LabRunCard(run: run, timeLimit: model.settings.polishTimeout)
                            }
                        }
                    }
                }
                Text("Results and unsaved edits are kept until Birdtown Flow quits.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}

/// Neighbouring runs on the same test input, newest first.
private struct LabRunGroup: Identifiable {
    let runs: [LabBench.Run]

    /// The oldest run's: new runs join at the top, so the group keeps its identity (and its
    /// cards their state) while a Run All batch fills in.
    var id: UUID { runs[runs.count - 1].id }
    var input: LabBench.TestInput { runs[0].testInput }

    static func groups(_ runs: [LabBench.Run]) -> [LabRunGroup] {
        PolishLabResults.consecutiveGroups(runs) { $0.testInput }.map(LabRunGroup.init(runs:))
    }
}

/// Names the text a group of results ran on, with the style and app it stood in for. A group
/// from an earlier test says so and can put its text back in the test card.
private struct LabRunGroupHeader: View {
    let group: LabRunGroup
    @Environment(AppModel.self) private var model

    var body: some View {
        let bench = model.bench
        let input = group.input
        let isCurrent = input == bench.currentTestInput
        HStack(alignment: .center, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("“\(PolishLabResults.excerpt(input.text, maxWords: Self.excerptWords))”")
                    .font(Typography.callout)
                    .foregroundStyle(isCurrent ? Palette.inkSecondary : Palette.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(input.text)
                Text(detail(input, isCurrent: isCurrent))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The text and its details read as one header; the button stays its own control.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if !isCurrent {
                Button("Use This Text") { bench.useTestInput(of: group.runs[0]) }
                    .buttonStyle(.flowGhost)
                    .controlSize(.small)
                    .disabled(bench.isRunning)
                    .help("Put this text, style and app back in Test, to run it again")
            }
        }
    }

    /// Enough to recognise a text; the full text is on the tooltip.
    private static let excerptWords = 24

    private func detail(_ input: LabBench.TestInput, isCurrent: Bool) -> String {
        let count = group.runs.count
        var parts = [input.style.title, input.appName ?? input.category.title,
                     count == 1 ? "1 result" : "\(count) results"]
        if !isCurrent { parts.append("Earlier text") }
        return parts.joined(separator: " · ")
    }
}

private struct LabRunCard: View {
    let run: LabBench.Run
    /// Dictation's polish time limit, in seconds.
    let timeLimit: Double

    @State private var showsReply = false
    @State private var didCopy = false

    var body: some View {
        Card(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(run.configuration.displayName)
                            .font(Typography.headline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        if run.wasEdited {
                            Badge(text: "Unsaved edits", tone: .warning)
                        }
                        Spacer(minLength: Spacing.s)
                        verdictBadge
                    }
                    Text(contextLine)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                        .lineLimit(1)
                }
                if let result = run.result {
                    content(result)
                } else {
                    HStack(spacing: Spacing.s) {
                        ProgressView().controlSize(.small)
                        Text("Polishing…")
                            .font(Typography.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
        }
    }

    /// The text, style and app are on the group's header above.
    private var contextLine: String {
        let time = run.ranAt.formatted(date: .omitted, time: .shortened)
        return [run.configuration.summary, time].joined(separator: " · ")
    }

    @ViewBuilder
    private var verdictBadge: some View {
        switch run.result?.verdict {
        case .some(.accepted):
            Badge(text: "Accepted", symbol: "checkmark.circle.fill", tone: .success)
        case .some(.rejected):
            Badge(text: "Original kept", symbol: "shield.lefthalf.filled", tone: .warning)
                .help("PolishGuard refused the reply, so dictation would type the text after Birdtown Flow's own cleanup and your dictionary.")
        case .some(.failed):
            Badge(text: "Failed", symbol: "xmark.octagon.fill", tone: .danger)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func content(_ result: PolishService.LabResult) -> some View {
        switch result.verdict {
        case .failed(let message):
            HStack(spacing: Spacing.m) {
                Text(message)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if run.needsSettings {
                    SettingsLink {
                        Text("Open Settings")
                    }
                    .buttonStyle(.flowSecondary)
                    .controlSize(.small)
                }
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(Palette.dangerSoft))
            timings(result)
        case .accepted:
            diff
            timings(result)
        case .rejected(let reply, let reason):
            // The diff is Birdtown Flow's own cleanup and the dictionary, not the model's edit.
            Text("Without polish, dictation would type:")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
            diff
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.warning)
                    Text(reason)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.s)
                    Button(showsReply ? "Hide the reply" : "Show the reply") { showsReply.toggle() }
                        .buttonStyle(.flowGhost)
                        .controlSize(.small)
                }
                .font(Typography.caption)
                if showsReply {
                    ScrollView {
                        Text(reply)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: Layout.Lab.replyMaxHeight)
                    .padding(Spacing.m)
                    .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(Palette.sunken))
                }
            }
            timings(result)
        }
    }

    /// What was heard against what would be typed: struck-through words went, tinted ones arrived.
    private var diff: some View {
        let segments = WordDiff.diff(original: run.input, revised: run.output)
        return Text(Self.attributed(segments))
            .font(Typography.transcript)
            .lineSpacing(Spacing.transcriptLine)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(run.output)
            .accessibilityValue(Self.spokenChanges(segments))
    }

    /// The diff in words for VoiceOver, which can't hear strikethrough or tint.
    static func spokenChanges(_ segments: [WordDiff.Segment]) -> String {
        var removed: [String] = []
        var added: [String] = []
        for segment in segments {
            switch segment {
            case .same: break
            case .removed(let words): removed.append(Self.oneLine(words))
            case .added(let words): added.append(Self.oneLine(words))
            }
        }
        var parts: [String] = []
        if !removed.isEmpty { parts.append("Removed: " + removed.joined(separator: ", ")) }
        if !added.isEmpty { parts.append("Added: " + added.joined(separator: ", ")) }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ". ")
    }

    /// Paragraph breaks read as plain gaps.
    private static func oneLine(_ words: String) -> String {
        words.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// Spelled out per attribute: on macOS, `foregroundColor` and friends also exist for AppKit.
    private typealias SwiftUIAttributes = AttributeScopes.SwiftUIAttributes

    static func attributed(_ segments: [WordDiff.Segment]) -> AttributedString {
        var text = AttributedString()
        for (index, segment) in segments.enumerated() {
            // A segment ending in a paragraph break needs no space before the next one.
            if index > 0, text.characters.last?.isNewline != true { text += AttributedString(" ") }
            let words: String
            switch segment {
            case .same(let w), .removed(let w), .added(let w): words = w
            }
            // The trailing break goes in unstyled, so a tint or strike doesn't run across it.
            let body = String(words.reversed().drop(while: \.isNewline).reversed())
            var part = AttributedString(body)
            switch segment {
            case .same:
                part[SwiftUIAttributes.ForegroundColorAttribute.self] = Palette.ink
            case .removed:
                part[SwiftUIAttributes.ForegroundColorAttribute.self] = Palette.danger
                part[SwiftUIAttributes.BackgroundColorAttribute.self] = Palette.dangerSoft
                part[SwiftUIAttributes.StrikethroughStyleAttribute.self] = Text.LineStyle(pattern: .solid, color: Palette.danger)
            case .added:
                part[SwiftUIAttributes.ForegroundColorAttribute.self] = Palette.success
                part[SwiftUIAttributes.BackgroundColorAttribute.self] = Palette.successSoft
            }
            text += part
            text += AttributedString(String(words.dropFirst(body.count)))
        }
        return text
    }

    private func timings(_ result: PolishService.LabResult) -> some View {
        let isClaudeCode = run.configuration.provider == .claudeCode
        // What a dictation would wait: Claude Code's own time when this run had to start it
        // first, since dictation starts it while you talk.
        let wait = isClaudeCode && result.startedCold
            ? result.sessionMilliseconds ?? result.totalMilliseconds
            : result.totalMilliseconds
        let startup = isClaudeCode && result.startedCold && result.sessionMilliseconds != nil
            ? max(0, result.totalMilliseconds - wait) : 0
        var isFailure = false
        if case .failed = result.verdict { isFailure = true }
        let counts = WordDiff.counts(original: run.input, revised: run.output)
        return HStack(spacing: Spacing.m) {
            if wait > 0 {
                metric("Wait", Self.format(wait))
                    .help("How long dictation would wait for this polish")
            }
            if let model = result.modelMilliseconds {
                metric("Model", Self.format(model))
                    .help("Time spent on the model, inside Claude Code")
            }
            if startup > 0 {
                Text("+\(Self.format(startup)) starting Claude Code")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .help("This run started Claude Code first. Dictation starts it while you talk, so it wouldn't wait for this.")
            }
            if !isFailure, Double(wait) / 1000 > timeLimit {
                Badge(text: "Over the \(Int(timeLimit)) s limit", symbol: "timer", tone: .warning)
                    .help("Dictation gives up after \(Int(timeLimit)) s and types the unpolished text.")
            }
            if !isFailure {
                metric("Words", "−\(counts.removed)  +\(counts.added)")
                    .help("Words removed and added, from what was heard to what would be typed")
            }
            Spacer(minLength: Spacing.s)
            if !isFailure {
                IconButton(symbol: didCopy ? "checkmark" : "doc.on.doc", label: didCopy ? "Copied" : "Copy the result") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.output, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: Motion.confirmation)
                        didCopy = false
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .foregroundStyle(Palette.inkTertiary)
            Text(value)
                .foregroundStyle(Palette.inkSecondary)
                .monospacedDigit()
        }
        .font(Typography.caption)
    }

    static func format(_ milliseconds: Int) -> String {
        guard milliseconds >= 1000 else { return "\(milliseconds) ms" }
        return (Double(milliseconds) / 1000).formatted(.number.precision(.fractionLength(2))) + " s"
    }
}

// MARK: - Fields

/// A choice drawn like the Lab's inset fields: the value and a chevron in a sunken well,
/// opening a menu with the current one ticked.
private struct LabPicker<Value: Hashable>: View {
    let label: String
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: Spacing.s) {
                Text(title(selection))
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.horizontal, Spacing.m)
            .frame(height: Layout.Lab.fieldHeight)
            .labWell()
            .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(label)
        .accessibilityValue(title(selection))
    }
}

/// A caption over a control, like `LabeledInput`'s.
private struct LabField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkSecondary)
            content
        }
    }
}

/// The app's inset text field (`LabeledInput`'s), without a label of its own, with room
/// for a control at its trailing end inside the well.
private struct LabTextInput<Accessory: View>: View {
    let title: String
    @Binding var text: String
    var prompt: String
    let accessory: Accessory

    @FocusState private var isFocused: Bool

    init(_ title: String, text: Binding<String>, prompt: String = "", @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            TextField(title, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .focused($isFocused)
            accessory
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: Layout.Lab.fieldHeight)
        .labWell(isFocused: isFocused)
    }
}

extension LabTextInput where Accessory == EmptyView {
    init(_ title: String, text: Binding<String>, prompt: String = "") {
        self.init(title, text: text, prompt: prompt) { EmptyView() }
    }
}

/// The sunken well every Lab input sits in: a hairline at rest, Signal blue while it has focus.
private struct LabWell: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        content
            .background(shape.fill(Palette.sunken))
            .overlay(shape.strokeBorder(
                isFocused ? Palette.accent : Palette.hairline,
                lineWidth: isFocused ? Layout.Main.focusRing : Layout.Main.hairline
            ))
    }
}

extension View {
    fileprivate func labWell(isFocused: Bool = false) -> some View {
        modifier(LabWell(isFocused: isFocused))
    }
}

extension PolishConfiguration {
    /// The name, or "Untitled" when it's been cleared, so copy never shows empty quotes.
    fileprivate var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : name
    }

    /// `summary` without the model: "Claude Code · Low effort".
    fileprivate var providerAndEffort: String {
        var parts = [Self.providerTitle(provider)]
        if usesEffort { parts.append(effort == .standard ? "Default effort" : "\(effort.title) effort") }
        return parts.joined(separator: " · ")
    }
}
