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
    var onSelect: ((_ additive: Bool) -> Void)?
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var showsOriginal: Bool
    @State private var didCopy = false
    @State private var copyReset: Task<Void, Never>?
    @State private var isRetrying = false
    @State private var isAddingWord = false

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        record: HistoryRecord,
        player: AudioPlayback,
        isSelected: Bool = false,
        isHighlighted: Bool = false,
        showsOriginal: Bool = false,
        onSelect: ((_ additive: Bool) -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) {
        self.record = record
        self.player = player
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
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
                    OriginalPanel(record: record)
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
            onSelect?(NSEvent.modifierFlags.contains(.command))
        }
        .contextMenu { menuItems }
        .sheet(isPresented: $isAddingWord) {
            DictionaryEditorSheet(original: nil, kind: .correction, context: record.finalText) { entry in
                model.dictionary.add(entry)
            }
        }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: showsOriginal)
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(appTitle), \(record.createdAt.formatted(date: .omitted, time: .shortened))")
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            Text(appTitle)
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
                    Text(record.hasText ? record.finalText : record.rawText)
                        .font(Typography.transcript)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineSpacing(Spacing.transcriptLine)
                        .lineLimit(Layout.Main.transcriptLines)
                }
                Text(record.errorMessage ?? "Something went wrong while transcribing.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.m) {
                    Button {
                        retry()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            if isRetrying {
                                ProgressView().controlSize(.mini).tint(Palette.onEmber)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isRetrying ? "Retrying…" : "Retry")
                        }
                    }
                    .buttonStyle(.murmurPrimary)
                    .controlSize(.small)
                    .disabled(isRetrying)
                    Text("The audio is saved, so nothing you said is lost.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
        case .empty, .cancelled:
            Text(record.outcome == .empty ? "No speech was heard." : "Cancelled before anything was typed.")
                .font(Typography.transcript)
                .italic()
                .foregroundStyle(Palette.inkTertiary)
        case .inserted, .copied:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(record.finalText)
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(Spacing.transcriptLine)
                    .lineLimit(isExpanded ? nil : Layout.Main.transcriptLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if isLong {
                    Button(isExpanded ? "Show less" : "Show more") { isExpanded.toggle() }
                        .buttonStyle(.plain)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            if let polisher = record.polishedBy, polisher != .off {
                Badge(text: "Polished · \(polisher.title)", symbol: "sparkles")
            }
            if correctionCount > 0 {
                Badge(
                    text: correctionCount == 1 ? "1 correction" : "\(correctionCount) corrections",
                    symbol: "character.book.closed"
                )
            }
            if !record.snippets.isEmpty {
                Badge(text: record.snippets.count == 1 ? "Snippet" : "\(record.snippets.count) snippets",
                      symbol: "text.badge.plus")
            }
            if record.outcome == .copied {
                Badge(text: "On clipboard", symbol: "doc.on.clipboard")
                    .help("There was no text field to type into, so Murmur left the text on the clipboard.")
            }
            Text(meta)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkTertiary)
                .lineLimit(1)
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
            IconButton(symbol: "text.insert", label: "Paste into the app you were using") {
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
        .buttonStyle(IconButtonStyle(tint: isPlaying ? Palette.ink : Palette.inkSecondary))
        .disabled(!hasAudio)
        .help(hasAudio ? (isPlaying ? "Stop" : "Play audio") : "This recording's audio is no longer kept")
        .accessibilityLabel(isPlaying ? "Stop audio" : "Play audio")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Copy", systemImage: "doc.on.doc") { copy() }
            .disabled(!record.hasText)
        Button("Paste Again", systemImage: "text.insert") { model.controller.insert(record) }
            .disabled(!record.hasText)
        Button(player.isPlaying(record.id) ? "Stop Audio" : "Play Audio", systemImage: "play") {
            player.toggle(record.id, url: audioURL)
        }
        .disabled(audioURL == nil)
        Divider()
        Button("Retry Transcription", systemImage: "arrow.clockwise") { retry() }
            .disabled(audioURL == nil || isRetrying)
        Button(showsOriginal ? "Hide Original" : "Show Original", systemImage: "text.magnifyingglass") {
            showsOriginal.toggle()
        }
        Button("Add a Word to Dictionary…", systemImage: "character.book.closed") {
            isAddingWord = true
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
    }

    @ViewBuilder
    private var rowFill: some View {
        if isSelected || isHighlighted {
            Palette.emberSoft
        } else if isHovered {
            Palette.surfaceHover
        } else {
            Palette.surface
        }
    }

    // MARK: - Derived

    private var showsActions: Bool {
        isHovered || isSelected || didCopy || player.isPlaying(record.id)
    }

    private var audioURL: URL? { model.history.audioURL(for: record) }

    private var correctionCount: Int { record.corrections.reduce(0) { $0 + $1.count } }

    /// Whether the text probably runs past `transcriptLines`: a cheap estimate from
    /// paragraph lengths, since SwiftUI can't report truncation.
    private var isLong: Bool {
        let perLine = Double(Layout.Main.transcriptCharsPerLine)
        let lines = record.finalText.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, Int((Double($1.count) / perLine).rounded(.up))) }
        return lines > Layout.Main.transcriptLines
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
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.finalText, forType: .string)
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
        isRetrying = true
        Task {
            await model.controller.retry(record)
            isRetrying = false
        }
    }
}

/// What the engine heard versus what Murmur wrote, and what changed in between.
struct OriginalPanel: View {
    let record: HistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Heard").eyebrowStyle()
                Text(record.rawText.isEmpty ? "Nothing was recognized." : record.rawText)
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(Spacing.transcriptLine)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !record.corrections.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Dictionary").eyebrowStyle()
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
                    timing("Polished by \(polisher.title)", record.timings.polishMs)
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
