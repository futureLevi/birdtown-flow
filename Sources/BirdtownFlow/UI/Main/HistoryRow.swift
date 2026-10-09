import Accessibility
import AppKit
import MurmurDictionary
import MurmurKit
import SwiftUI

/// One dictation: where it went, what was written, what the pipeline did, and every action
/// you might want — on hover, in the ⋯ menu and in the context menu.
struct HistoryRow: View {
    /// Leading inset that lines dividers up with the row's text column.
    static let textInset = Spacing.l + Layout.Main.rowIcon + Spacing.m

    let record: HistoryRecord
    let player: AudioPlayback
    var isSelected: Bool
    var isHighlighted: Bool
    /// The History search, so the row can mark where it matched.
    var query: String
    var onSelect: ((ListSelection<UUID>.Click) -> Void)?
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var showsOriginal: Bool
    @State private var didCopy = false
    @State private var copyReset: Task<Void, Never>?
    @State private var isAddingWord = false
    @FocusState private var isPlayFocused: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    init(
        record: HistoryRecord,
        player: AudioPlayback,
        isSelected: Bool = false,
        isHighlighted: Bool = false,
        showsOriginal: Bool = false,
        query: String = "",
        onSelect: ((ListSelection<UUID>.Click) -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) {
        self.record = record
        self.player = player
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.query = query
        self.onSelect = onSelect
        self.onDelete = onDelete
        _showsOriginal = State(initialValue: showsOriginal)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            AppIcon(bundleID: record.context?.bundleID, name: record.context?.appName, size: Layout.Main.rowIcon)
            VStack(alignment: .leading, spacing: Spacing.s) {
                header
                content
                footer
                if showsOriginal {
                    OriginalPanel(record: record, query: query)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(rowFill)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            onSelect?(flags.contains(.shift) ? .extend : flags.contains(.command) ? .toggle : .plain)
        }
        .contextMenu { menuItems }
        .sheet(isPresented: $isAddingWord) {
            DictionaryEditorSheet(original: nil, kind: .correction, context: record.finalText) { entry in
                model.dictionary.add(entry)
            }
            .environment(model)
        }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: showsOriginal)
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(appTitle), \(record.createdAt.formatted(date: .omitted, time: .shortened))")
        // The hover buttons are invisible (and so missing from the accessibility tree) most of
        // the time; name the row's main actions so VoiceOver offers them directly.
        .accessibilityActions { accessibilityActionItems }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            Text(Self.highlighted(appTitle, query: query))
                .font(Typography.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(record.createdAt, format: .dateTime.hour().minute())
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
            if record.outcome == .failed {
                Badge(text: "Failed", symbol: "exclamationmark.triangle.fill", tone: .danger)
            }
            Spacer(minLength: Spacing.s)
            actions
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)
        }
        .frame(height: Layout.Main.iconButton)
    }

    @ViewBuilder
    private var content: some View {
        switch record.outcome {
        case .failed:
            VStack(alignment: .leading, spacing: Spacing.s) {
                if record.hasText || !record.rawText.isEmpty {
                    Text(Self.highlighted(record.hasText ? record.finalText : record.rawText, query: query))
                        .font(Typography.transcript)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineSpacing(Spacing.transcriptLine)
                        .lineLimit(Layout.Main.transcriptLines)
                }
                Text(record.errorMessage ?? "Something went wrong while transcribing.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                retryFooter
            }
        case .empty, .cancelled:
            Text(record.outcome == .empty ? "No speech was heard." : "Cancelled before anything was typed.")
                .font(Typography.transcript)
                .italic()
                .foregroundStyle(Palette.inkTertiary)
        case .inserted, .copied:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                let preview = transcriptPreview
                Text(Self.highlighted(preview.text, ranges: preview.ranges))
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(Spacing.transcriptLine)
                    .lineLimit(isExpanded ? nil : Layout.Main.transcriptLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    // The old text stays readable but recedes while new text is on its way.
                    .opacity(isRetrying ? Interaction.dimmedOpacity : 1)
                if isLong {
                    Button(isExpanded ? "Show less" : "Show more") { isExpanded.toggle() }
                        .buttonStyle(RowLinkButtonStyle())
                        .padding(.top, Spacing.xxs)
                        .accessibilityLabel(isExpanded ? "Show less of this dictation" : "Show all of this dictation")
                }
                if let reason = keptReason {
                    keptNotice(reason)
                }
            }
        }
        if matchedOnlyInHeard {
            heardMatchNotice
        }
    }

    /// The transcript as the row shows it. Collapsed, an email's "Hi Priya,\n\n" would spend
    /// two of three lines on the greeting, so line breaks fold into spaces like Mail's
    /// previews; and when a search hit sits past the first lines, the preview starts "…" far
    /// enough before it to fill the lines above the hit. Expanded shows the text exactly as it
    /// was typed.
    private var transcriptPreview: SearchHighlight.Preview {
        if isExpanded {
            return SearchHighlight.Preview(
                text: record.finalText,
                ranges: SearchHighlight.ranges(of: query, in: record.finalText)
            )
        }
        let flat = Self.flattened(record.finalText)
        guard isLong else {
            return SearchHighlight.Preview(text: flat, ranges: SearchHighlight.ranges(of: query, in: flat))
        }
        // Back up as far as the budget allows rather than a fixed few words, so the excerpt
        // fills the preview up to the hit instead of starting mid-sentence one line from the
        // end. The hit ends within the budget, leaving the last line for what follows it.
        let hitLength = query.trimmingCharacters(in: .whitespacesAndNewlines).count
        let lead = max(Self.minimumLead, Self.previewBudget - hitLength)
        return SearchHighlight.preview(of: flat, query: query, budget: Self.previewBudget, lead: lead)
    }

    /// Characters a collapsed preview can show before a match needs an excerpt: all but the
    /// last line, so the hit lands with some of its sentence after it.
    private static var previewBudget: Int {
        (Layout.Main.transcriptLines - 1) * Layout.Main.transcriptCharsPerLine
    }

    /// The least context an excerpt keeps before its hit (`SearchHighlight`'s default).
    private static let minimumLead = 40

    /// "Transcribe Again" gave nothing better, so the text above is the old one.
    private func keptNotice(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Palette.warning)
            Text("Couldn't transcribe this again: \(reason) Your text is unchanged.")
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Dismiss") { model.retries.dismissReason(record.id) }
                .buttonStyle(RowLinkButtonStyle())
        }
        .font(Typography.callout)
        .padding(.top, Spacing.xxs)
    }

    /// The search only matched what the engine heard (before cleanup and polish), which is
    /// out of sight until Show Original.
    private var heardMatchNotice: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(Palette.inkTertiary)
            Text("Matches what was heard, before cleanup")
                .foregroundStyle(Palette.inkSecondary)
            if !showsOriginal {
                Button("Show Original") { showsOriginal = true }
                    .buttonStyle(RowLinkButtonStyle())
            }
        }
        .font(Typography.callout)
    }

    /// Retry, and whether the audio is there to retry with. One disk check per pass.
    private var retryFooter: some View {
        let hasAudio = audioURL != nil
        return HStack(spacing: Spacing.m) {
            Button {
                retry()
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isRetrying {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRetrying ? "Retrying…" : "Retry")
                }
            }
            .buttonStyle(.flowSecondary)
            .controlSize(.small)
            .disabled(isRetrying || !hasAudio)
            .help(hasAudio ? "Transcribe the saved audio again" : "The audio for this dictation wasn't kept")
            Text(hasAudio
                 ? "The audio is saved, so nothing you said is lost."
                 : "The audio wasn't kept, so this one can't be retried.")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            // The failed layout shows progress on its Retry button; everything else here.
            if isRetrying && record.outcome != .failed {
                // A symbol rather than ProgressView: the native spinner ignores the accent and
                // draws a faint grey beside the blue label.
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .imageScale(.small)
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                    Text("Transcribing again…")
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.accent)
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
            if !isRetrying, model.retries.replaced[record.id] != nil {
                Button("Restore earlier text") { restoreEarlierText() }
                    .buttonStyle(RowLinkButtonStyle())
                    .fixedSize()
                    .help("Put back the text from before you transcribed this again")
            }
            if let polisher = record.polishedBy, polisher != .off {
                // A Lab configuration names itself; Settings' provider names the provider.
                Badge(text: "Polished · \(record.polishConfiguration ?? polisher.title)", symbol: "sparkles")
                    .help(record.polishConfiguration.map { "Lab configuration “\($0)”, on \(polisher.title)" } ?? "")
            }
            if correctionCount > 0 {
                Badge(
                    text: correctionCount == 1 ? "1 replacement" : "\(correctionCount) replacements",
                    symbol: "character.book.closed"
                )
            }
            if !record.snippets.isEmpty {
                Badge(text: record.snippets.count == 1 ? "Snippet" : "\(record.snippets.count) snippets",
                      symbol: "text.badge.plus")
            }
            if record.outcome == .copied {
                Badge(text: "On clipboard", symbol: "doc.on.clipboard")
                    .help("Birdtown Flow put this on the clipboard instead of typing it.")
            }
            Text(meta)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
                .lineLimit(1)
                .help(polishNote.map { record.polishedBy == nil ? "AI polish wasn't used: \($0)" : $0 } ?? "")
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.xxs) {
            if didCopy {
                Label("Copied", systemImage: "checkmark")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.success)
                    .padding(.horizontal, Spacing.s)
                    .transition(.opacity)
            } else {
                IconButton(symbol: "doc.on.doc", label: "Copy") { copy() }
                    .disabled(!record.hasText)
            }
            IconButton(symbol: "text.insert", label: "Paste Again") {
                model.controller.insert(record)
            }
            .disabled(!record.hasText)
            playButton
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(Typography.bodyEmphasis)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .frame(width: Layout.Main.iconButton, height: Layout.Main.iconButton)
            .help("More")
            .accessibilityLabel("More actions")
        }
    }

    private var playButton: some View {
        let isPlaying = player.isPlaying(record.id)
        let hasAudio = audioURL != nil
        return Button {
            player.toggle(record.id, url: audioURL)
        } label: {
            ZStack {
                if isPlaying {
                    ProgressRing(progress: player.progress)
                    Image(systemName: "stop.fill")
                        .font(Typography.eyebrow)
                        .imageScale(.small)
                } else {
                    Image(systemName: "play.fill")
                        .font(Typography.bodyEmphasis)
                }
            }
        }
        .buttonStyle(IconButtonStyle(tint: isPlaying ? Palette.ink : Palette.inkSecondary,
                                     drawsFocusRing: isPlayFocused))
        // Like its `IconButton` neighbours: the style draws the Signal blue focus ring.
        .focusEffectDisabled()
        .focused($isPlayFocused)
        .disabled(!hasAudio)
        .help(hasAudio ? (isPlaying ? "Stop" : "Play audio") : "This recording's audio is no longer kept")
        .accessibilityLabel(isPlaying ? "Stop audio" : "Play audio")
    }

    @ViewBuilder
    private var menuItems: some View {
        let hasAudio = audioURL != nil
        Button("Copy", systemImage: "doc.on.doc") { copy() }
            .disabled(!record.hasText)
        Button("Paste Again", systemImage: "text.insert") { model.controller.insert(record) }
            .disabled(!record.hasText)
        Button(player.isPlaying(record.id) ? "Stop Audio" : "Play Audio", systemImage: "play") {
            player.toggle(record.id, url: audioURL)
        }
        .disabled(!hasAudio)
        Divider()
        Button(retryTitle, systemImage: "arrow.clockwise") { retry() }
            .disabled(!hasAudio || isRetrying)
        if model.retries.replaced[record.id] != nil {
            Button("Restore Earlier Text", systemImage: "arrow.uturn.backward") { restoreEarlierText() }
                .disabled(isRetrying)
        }
        Button(showsOriginal ? "Hide Original" : "Show Original", systemImage: "text.magnifyingglass") {
            showsOriginal.toggle()
        }
        Button("Add a Replacement…", systemImage: "character.book.closed") {
            isAddingWord = true
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
    }

    /// VoiceOver's custom actions for the row. Not `menuItems`: that has dividers and opens a
    /// sheet, neither of which belongs in the actions rotor.
    @ViewBuilder
    private var accessibilityActionItems: some View {
        if record.hasText {
            Button("Copy") { copy() }
            Button("Paste Again") { model.controller.insert(record) }
        }
        if audioURL != nil {
            Button(player.isPlaying(record.id) ? "Stop Audio" : "Play Audio") {
                player.toggle(record.id, url: audioURL)
            }
            if !isRetrying {
                Button(retryTitle) { retry() }
            }
        }
        if !isRetrying, model.retries.replaced[record.id] != nil {
            Button("Restore Earlier Text") { restoreEarlierText() }
        }
        Button(showsOriginal ? "Hide Original" : "Show Original") { showsOriginal.toggle() }
        Button("Delete", role: .destructive) { onDelete() }
    }

    @ViewBuilder
    private var rowFill: some View {
        if isSelected || isHighlighted {
            Palette.accentSoft
        } else if isHovered {
            Palette.surfaceHover
        } else {
            Palette.surface
        }
    }

    // MARK: - Derived

    private var showsActions: Bool {
        // VoiceOver drops invisible views, so keep the buttons in its reach while it runs.
        isHovered || isSelected || didCopy || player.isPlaying(record.id) || voiceOverEnabled
    }

    private var audioURL: URL? { model.history.audioURL(for: record) }

    private var isRetrying: Bool { model.retries.isRetrying(record.id) }

    /// A failed dictation is retried; one that worked is transcribed again, keeping its text
    /// if the new attempt does worse than fail to improve it.
    private var retryTitle: String {
        Retranscription.hasGoodText(record) ? "Transcribe Again" : "Retry Transcription"
    }

    private var keptReason: String? { model.retries.keptReasons[record.id] }

    private var matchedOnlyInHeard: Bool {
        // Failed rows already show the heard text when there's nothing else.
        guard record.outcome == .inserted || record.outcome == .copied else { return false }
        let fields = SearchHighlight.fields(of: record, matching: query)
        return fields.contains(.heard) && !fields.contains(.text) && !fields.contains(.app)
    }

    private var correctionCount: Int { record.corrections.reduce(0) { $0 + $1.count } }

    /// Whether the text probably runs past `transcriptLines`: a cheap estimate from
    /// paragraph lengths, since SwiftUI can't report truncation.
    private var isLong: Bool {
        // Line breaks always count as "more": the collapsed preview folds them away.
        if record.finalText.contains(where: \.isNewline) { return true }
        let lines = (Double(record.finalText.count) / Double(Layout.Main.transcriptCharsPerLine)).rounded(.up)
        return Int(lines) > Layout.Main.transcriptLines
    }

    static func flattened(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// "Slack", or "Gmail in Google Chrome" when the window title gives a web app away.
    private var appTitle: String {
        let app = record.context?.appName ?? "Unknown app"
        guard let title = record.context?.windowTitle,
              let webApp = Self.webApps.first(where: { title.localizedCaseInsensitiveContains($0) }),
              webApp != app
        else { return app }
        return "\(webApp) in \(app)"
    }

    private static let webApps = ["Gmail", "Outlook", "Slack", "Linear", "Notion", "Google Docs", "WhatsApp"]

    private var meta: String {
        var parts: [String] = []
        if let style = record.style { parts.append(style.title) }
        if !record.engine.isEmpty { parts.append(record.engine) }
        if record.audioDuration > 0 {
            parts.append(Duration.seconds(record.audioDuration).formatted(.time(pattern: .minuteSecond)))
        }
        if let wpm = record.wordsPerMinute { parts.append("\(wpm) wpm") }
        if let note = polishNote {
            // A long dictation polished in parts was polished, even if some parts weren't.
            parts.append(record.polishedBy == nil ? "Not polished · \(Self.shortNote(note))" : Self.shortNote(note))
        }
        return parts.joined(separator: " · ")
    }

    /// Core keeps polish fallback notes ("Timed out after 4 s", "Partly polished · 1 of 4
    /// parts kept as dictated (timed out after 4 s)") on records that succeeded. They're
    /// information, not errors: only `.failed` records show their message in red.
    private var polishNote: String? {
        guard record.outcome != .failed,
              let note = record.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty
        else { return nil }
        return note
    }

    /// "Rewrite rejected: it changed what was said" → "rewrite rejected". Acronyms keep case.
    static func shortNote(_ note: String) -> String {
        let head = (note.split(separator: ":", maxSplits: 1).first.map(String.init) ?? note)
            .trimmingCharacters(in: .whitespaces)
        guard let first = head.split(separator: " ").first, first != first.uppercased() else { return head }
        return head.prefix(1).lowercased() + head.dropFirst()
    }

    // MARK: - Actions

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.finalText, forType: .string)
        flashCopied()
    }

    private func flashCopied() {
        didCopy = true
        copyReset?.cancel()
        copyReset = Task {
            try? await Task.sleep(for: Motion.confirmation)
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    private func retry() {
        guard !isRetrying else { return }
        let record = record
        AccessibilityNotification.Announcement("Transcribing again").post()
        Task {
            let resolution = await model.retries.retry(
                record, controller: model.controller, history: model.history
            )
            switch resolution {
            case .keptPrevious?:
                let reason = model.retries.keptReasons[record.id] ?? ""
                AccessibilityNotification.Announcement(
                    "Couldn't transcribe this again: \(reason) Your text is unchanged."
                ).post()
            case .some:
                // New text goes to the clipboard; say so where the user looked.
                if model.history.record(id: record.id)?.outcome == .copied {
                    flashCopied()
                    AccessibilityNotification.Announcement("Transcribed again and copied").post()
                }
            case nil:
                break
            }
        }
    }

    private func restoreEarlierText() {
        model.retries.restore(record.id, in: model.history)
        AccessibilityNotification.Announcement("Earlier text restored").post()
    }

    // MARK: - Search highlighting

    static func highlighted(_ text: String, query: String) -> AttributedString {
        highlighted(text, ranges: SearchHighlight.ranges(of: query, in: text))
    }

    /// `text` with each search match washed in the find-highlight colour.
    static func highlighted(_ text: String, ranges: [Range<String.Index>]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges {
            guard let run = Range(range, in: attributed) else { continue }
            // Spelled out: AppKit's scope has a `backgroundColor` too (an NSColor).
            attributed[run][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Palette.historySearchMatch
            // Weight too, so the hit doesn't rest on colour alone.
            attributed[run].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}

/// "Show more" / "Show less": a Signal blue text link that underlines on hover and dims on press.
private struct RowLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowLinkBody(configuration: configuration)
    }
}

private struct RowLinkBody: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(Typography.caption)
            .foregroundStyle(Palette.accent)
            .underline(isHovered)
            .opacity(configuration.isPressed ? Interaction.dimmedOpacity : 1)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
    }
}

/// What the engine heard versus what was written, and what changed in between.
struct OriginalPanel: View {
    let record: HistoryRecord
    var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Heard").eyebrowStyle()
                Text(record.rawText.isEmpty
                     ? AttributedString("Nothing was recognized.")
                     : HistoryRow.highlighted(record.rawText, query: query))
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(Spacing.transcriptLine)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !record.corrections.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Replacements").eyebrowStyle()
                    ForEach(record.corrections, id: \.self) { correction in
                        HStack(spacing: Spacing.s) {
                            Text(correction.from)
                                .font(Typography.body)
                                .foregroundStyle(Palette.inkSecondary)
                            Image(systemName: "arrow.right")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkTertiary)
                            Text(correction.to)
                                .font(Typography.bodyEmphasis)
                                .foregroundStyle(Palette.ink)
                            if correction.count > 1 {
                                Text("×\(correction.count)")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.inkTertiary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Heard \(correction.from), wrote \(correction.to)")
                    }
                }
            }
            HStack(spacing: Spacing.l) {
                timing("Transcribed", record.timings.transcribeMs)
                if let polisher = record.polishedBy, polisher != .off {
                    timing(record.polishConfiguration.map { "Polished by \(polisher.title) (Lab: \($0))" }
                               ?? "Polished by \(polisher.title)", record.timings.polishMs)
                }
                timing("Total", record.timings.totalMs)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Palette.sunken))
    }

    @ViewBuilder
    private func timing(_ label: String, _ milliseconds: Int) -> some View {
        if milliseconds > 0 {
            HStack(spacing: Spacing.xs) {
                Text(label)
                    .foregroundStyle(Palette.inkTertiary)
                Text(Self.format(milliseconds))
                    .foregroundStyle(Palette.inkSecondary)
                    .monospacedDigit()
            }
            .font(Typography.caption)
        }
    }

    static func format(_ milliseconds: Int) -> String {
        guard milliseconds >= 1000 else { return "\(milliseconds) ms" }
        return (Double(milliseconds) / 1000).formatted(.number.precision(.fractionLength(1))) + " s"
    }
}
