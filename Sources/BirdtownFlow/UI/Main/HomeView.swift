import AppKit
import MurmurKit
import SwiftUI

/// Home: an open canvas. The voice-field artwork sits behind the toolbar and the content, the
/// greeting sits on it, and Recent dictation owns the main column with "Your setup" and a quiet
/// "This week" beside it (under it in a narrow window). Anything that needs fixing is a banner
/// between the greeting and the columns.
struct HomeView: View {
    let status: SystemStatus

    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player = AudioPlayback()
    @State private var pendingStats = ViewMemo<PendingStatsKey, DictationStats>()
    /// The detail column's width, measured; until then, as the window opens.
    @State private var width = Layout.Home.designWidth

    /// What Home's numbers depend on while a delete can still be undone.
    private struct PendingStatsKey: Equatable {
        var records: [HistoryRecord]
        var pending: Set<UUID>
    }

    var body: some View {
        let scale = Layout.Home.Scale(width: width)
        let records = model.history.records
        // A delete waiting out its undo window is hidden here as on History, and left out of
        // the numbers too.
        let pending = model.historyDeletion.pending
        // Cached in the store: this body re-runs on every history change, and the full
        // computation scans the whole history. While a delete is pending (a few seconds) the
        // store's cache would still count it, so the numbers come from a memo keyed by what
        // they depend on instead.
        let stats = pending.isEmpty
            ? model.history.stats()
            : pendingStats.value(for: PendingStatsKey(records: records, pending: pending)) { key in
                DictationStats.compute(from: key.records.filter { !key.pending.contains($0.id) })
            }
        // The same array, uncopied, when nothing is hidden.
        let visible = model.historyDeletion.visible(records)
        let recentRecords = Array(visible.prefix(Layout.Home.recentCount))
        // A first dictation still being recorded has a row already, but not one to show.
        let isFirstRun = visible.isEmpty && pending.isEmpty
        ZStack(alignment: .topTrailing) {
            artwork(scale)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    intro(scale: scale)
                    if HomeBanners.isVisible(status: status, hasCompletedOnboarding: model.settings.hasCompletedOnboarding) {
                        HomeBanners(status: status)
                            .padding(.bottom, Layout.Home.bannersBottom)
                    }
                    columns(scale: scale, stats: stats, recent: recentRecords, isFirstRun: isFirstRun)
                }
                .frame(maxWidth: Layout.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.page)
                .frame(maxWidth: .infinity)
            }
            // Room to scroll the last row clear of the undo toast while it's up.
            .contentMargins(.bottom, pending.isEmpty ? 0 : Layout.Main.floatingBarClearance, for: .scrollContent)
            // The same Undo as History's, so a delete from Recent can be taken back (⌘Z too).
            .overlay(alignment: .bottom) { HistoryUndoToast() }
            // Home starts at the window's top so the art can sit behind the toolbar; the page
            // itself scrolls under it, as every other page does.
            .padding(.top, Layout.Toolbar.height)
        }
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: model.historyDeletion.pending)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onDisappear { player.stop() }
    }

    // MARK: - Artwork

    /// The voice field, on the canvas behind the toolbar and the page: no card, border or
    /// shadow. It's clipped to the column, and nothing it covers loses its text.
    private func artwork(_ scale: Layout.Home.Scale) -> some View {
        let field = scale.field
        return VoiceField(width: field.width, showsBars: field.showsBars, pinnedSeconds: preview.fieldPhase)
            .opacity(field.opacity)
            // The art's right edge sits `trailingInset` inside the column, or past it.
            .offset(x: -field.trailingInset, y: field.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .clipped()
    }

    // MARK: - Greeting

    private func intro(scale: Layout.Home.Scale) -> some View {
        let contentWidth = min(width - 2 * Spacing.page, Layout.contentMaxWidth)
        return VStack(alignment: .leading, spacing: Layout.Home.introSpacing) {
            Text(Self.greeting(name: preview.firstName ?? Self.firstName) + ".")
                .font(Typography.greeting(scale))
                .tracking(Tracking.greeting(scale))
                .foregroundStyle(Palette.heading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            hint(scale: scale)
        }
        // Stays clear of the artwork on the right.
        .frame(maxWidth: max(0, contentWidth * scale.copyFraction), alignment: .leading)
        .padding(.top, Layout.Home.introTop)
        .padding(.bottom, Layout.Home.introBottom)
        .frame(maxWidth: .infinity, minHeight: scale.introMinHeight, alignment: .leading)
        .padding(.bottom, scale.introMargin)
    }

    /// "Hold fn anywhere to dictate. Release to insert.", with the key as a keycap.
    private func hint(scale: Layout.Home.Scale) -> some View {
        HStack(alignment: .center, spacing: Layout.Home.hintSpacing) {
            Text("Hold")
            KeyCap(label: status.pushToTalkKey)
            Text("anywhere to dictate. Release to insert.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Typography.greetingHint(scale))
        .foregroundStyle(Palette.inkSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold \(status.pushToTalkKey) anywhere to dictate. Release to insert.")
    }

    // MARK: - Columns

    /// Recent dictation beside the setup and week panels, or over them in a narrow window.
    @ViewBuilder
    private func columns(
        scale: Layout.Home.Scale,
        stats: DictationStats,
        recent: [HistoryRecord],
        isFirstRun: Bool
    ) -> some View {
        if scale.stacksColumns {
            VStack(alignment: .leading, spacing: Layout.Home.stackedGap) {
                mainColumn(recent: recent, isFirstRun: isFirstRun)
                HStack(alignment: .top, spacing: Layout.Home.sideBySideGap) {
                    HomeSetupCard()
                        .frame(maxWidth: .infinity, alignment: .top)
                    // No week to summarise before the first dictation.
                    if !isFirstRun {
                        WeekSummary(stats: stats)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: scale.columnGap) {
                mainColumn(recent: recent, isFirstRun: isFirstRun)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: Layout.Home.asideGap) {
                    HomeSetupCard()
                    if !isFirstRun {
                        WeekSummary(stats: stats)
                    }
                }
                .frame(width: scale.asideWidth)
            }
        }
    }

    @ViewBuilder
    private func mainColumn(recent: [HistoryRecord], isFirstRun: Bool) -> some View {
        if isFirstRun {
            FirstRunCard(keyName: status.pushToTalkKey)
        } else {
            VStack(alignment: .leading, spacing: Layout.Home.sectionHeaderBottom) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    Text("Recent dictation")
                        .font(Typography.title)
                        .tracking(Tracking.title)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Spacing.s)
                    Button {
                        model.section = .history
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("View history")
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                        }
                        .font(Typography.link)
                    }
                    .buttonStyle(TextLinkButtonStyle())
                }
                if !recent.isEmpty {
                    recentList(recent)
                }
            }
        }
    }

    /// The last few dictations in one card, a hairline between them.
    private func recentList(_ records: [HistoryRecord]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                if index > 0 {
                    RowDivider()
                }
                HistoryRow(
                    record: record,
                    player: player,
                    // A click opens the dictation in History, with all its actions and
                    // Show Original; the hover buttons still work in place.
                    onSelect: { _ in model.showHistory(revealing: record.id) },
                    onDelete: { HistoryUndoToast.delete([record.id], model: model, player: player) }
                )
                .accessibilityHint("Opens in History")
                .accessibilityAction(named: "Open in History") {
                    model.showHistory(revealing: record.id)
                }
            }
        }
        .cardSurface()
    }

    // MARK: - Greeting words

    static var firstName: String? {
        NSFullUserName().split(separator: " ").first.map(String.init)
    }

    static func greeting(name: String?, now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let salutation = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<23: "Good evening"
        default: "Working late"
        }
        guard let name, !name.isEmpty else { return salutation }
        return "\(salutation), \(name)"
    }
}

// MARK: - Your setup

/// Where dictation is tuned, one row each, linking to the screen that changes it.
private struct HomeSetupCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Layout.Home.setupHeadingSpacing) {
                Image(systemName: "gearshape")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                Text("Your setup")
                    .font(Typography.groupTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, Layout.Home.setupHeadingInsetSide)
            .padding(.top, Layout.Home.setupHeadingInsetTop)
            .padding(.bottom, Layout.Home.setupHeadingInsetBottom)
            RowDivider()
            HomeSetupRow(label: "Writing style", value: styleSummary, section: .style, tone: .violet) {
                model.section = .style
            }
            RowDivider()
            HomeSetupRow(label: "Text polish", value: polishSummary, section: .lab, tone: .accent) {
                model.section = .lab
            }
            RowDivider()
            HomeSetupRow(label: "Dictionary", value: dictionarySummary, section: .dictionary, tone: .teal) {
                model.section = .dictionary
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// One style for every kind of app, or a note that each has its own.
    private var styleSummary: String {
        let styles = Set(AppCategory.allCases.map { model.settings.style(for: $0) })
        if styles.count == 1, let only = styles.first {
            return "\(only.title) everywhere"
        }
        return "Adapted to each app"
    }

    /// The Lab configuration that polishes dictations, else the polish provider from Settings.
    private var polishSummary: String {
        let lab = model.lab
        var seen = Set<String>()
        let names = lab.assignedStyles
            .compactMap { lab.configuration(for: $0)?.name }
            .filter { seen.insert($0).inserted }
        if names.count == 1, let only = names.first {
            return only
        }
        if names.count > 1 {
            return "\(names.count) Lab setups"
        }
        let provider = model.settings.polishProvider
        return provider == .off ? "Off" : provider.title
    }

    private var dictionarySummary: String {
        let count = model.dictionary.visible.count
        switch count {
        case 0: return "No entries yet"
        case 1: return "1 custom entry"
        default: return "\(count) custom entries"
        }
    }
}

/// One row of "Your setup": a tinted symbol, what it is and its current value, and a chevron.
/// Keyboard focus draws Signal blue's ring just inside the row, since the card clips anything
/// outside it.
private struct HomeSetupRow: View {
    enum Tone { case accent, violet, teal }

    let label: String
    let value: String
    let section: SidebarSection
    let tone: Tone
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.Home.setupRowSpacing) {
                Image(systemName: section.symbol)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(foreground)
                    .frame(width: Layout.Home.setupSymbol, height: Layout.Home.setupSymbol)
                    .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(soft))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(label)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                    Text(value)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Spacing.s)
                Image(systemName: "chevron.right")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.icon)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Layout.Home.setupRowInsetSide)
            .padding(.vertical, Layout.Home.setupRowInsetVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Palette.editor : Color.clear)
            .contentShape(Rectangle())
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Palette.focus, lineWidth: Layout.Focus.width)
                        .padding(Layout.Focus.offset)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        // The ring above is the focus indicator; the system's would double it.
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel("\(label), \(value)")
        .accessibilityHint("Opens \(section.title)")
    }

    private var foreground: Color {
        switch tone {
        case .accent: Palette.accent
        case .violet: Palette.violet
        case .teal: Palette.teal
        }
    }

    private var soft: Color {
        switch tone {
        case .accent: Palette.accentSoft
        case .violet: Palette.violetSoft
        case .teal: Palette.tealSoft
        }
    }
}

// MARK: - Banners

/// Missing permissions and model trouble, each with the fix one click away.
private struct HomeBanners: View {
    let status: SystemStatus
    @Environment(AppModel.self) private var model

    /// Whether any banner below would show; keep in step with `body`.
    static func isVisible(status: SystemStatus, hasCompletedOnboarding: Bool) -> Bool {
        if !hasCompletedOnboarding || !status.microphone || !status.accessibility { return true }
        if !status.hotkeyActive { return true }
        switch status.model {
        case .notDownloaded, .downloading, .failed: return true
        case .loading, .ready: return false
        }
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            // Until setup is finished, its banner stands in for the permission banners below:
            // setup walks through the same grants, in order, with explanations.
            if !model.settings.hasCompletedOnboarding {
                Banner(
                    symbol: "checklist",
                    title: "Finish setting up Birdtown Flow",
                    message: "About a minute: permissions, your shortcut, and a first dictation.",
                    tone: .info
                ) {
                    // Finishing setup unblocks everything else: the screen's one primary action.
                    Button("Continue Setup") { OnboardingWindowController.shared.show(model: model) }
                        .buttonStyle(.flowPrimary)
                        .controlSize(.small)
                }
            } else {
                permissionBanners
            }
            modelBanner
        }
    }

    @ViewBuilder
    private var permissionBanners: some View {
        Group {
            if !status.microphone {
                Banner(
                    symbol: "mic.slash.fill",
                    title: "Birdtown Flow can't hear you yet",
                    message: "Allow microphone access so Birdtown Flow can listen while you hold \(status.pushToTalkKey).",
                    tone: .danger
                ) {
                    Button("Allow Microphone") {
                        Task {
                            if !(await Permissions.requestMicrophone()) {
                                Permissions.openMicrophoneSettings()
                            }
                            model.permissions.refresh()
                        }
                    }
                    .buttonStyle(.flowSecondary)
                    .controlSize(.small)
                }
            }
            if !status.accessibility {
                Banner(
                    symbol: "keyboard",
                    title: "Allow Accessibility to use \(status.pushToTalkKey)",
                    message: "Birdtown Flow needs it to notice your shortcut and to type into other apps.",
                    tone: .warning
                ) {
                    Button("Open Settings") { Permissions.openAccessibilitySettings() }
                        .buttonStyle(.flowSecondary)
                        .controlSize(.small)
                }
            } else if !status.hotkeyActive {
                // The sidebar used to say this; Home is now where anything broken shows.
                Banner(
                    symbol: "pause.circle",
                    title: "Your shortcut is paused",
                    message: "Birdtown Flow is reconnecting \(status.pushToTalkKey) automatically.",
                    tone: .warning
                ) {
                    Button("Retry") { model.controller.activate() }
                        .buttonStyle(.flowSecondary)
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var modelBanner: some View {
        switch status.model {
        case .downloading(let progress):
            Banner(
                symbol: "arrow.down",
                title: "Downloading \(status.engineName)",
                message: "A one-time \(status.engineDownloadSize) download. It runs privately on your Mac from then on.",
                tone: .info
            ) {
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    if let progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    SpectrumProgressBar(progress: progress)
                        .frame(width: Layout.Main.progressBarWidth)
                }
            }
        case .notDownloaded:
            Banner(
                symbol: "arrow.down",
                title: "Download the speech model",
                message: "\(status.engineName) runs privately on your Mac. It's a one-time \(status.engineDownloadSize) download.",
                tone: .info
            ) {
                Button("Download") { Task { await model.models.prepare() } }
                    .buttonStyle(.flowSecondary)
                    .controlSize(.small)
            }
        case .failed(let message):
            Banner(
                symbol: "exclamationmark.triangle.fill",
                title: "Speech model didn't load",
                message: message,
                tone: .danger
            ) {
                Button("Try Again") { Task { await model.models.prepare() } }
                    .buttonStyle(.flowSecondary)
                    .controlSize(.small)
            }
        case .loading, .ready:
            EmptyView()
        }
    }
}

// MARK: - Links

/// A text link in Signal blue, deep enough to read, dimming while pressed.
private struct TextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.accentInk)
            .opacity(configuration.isPressed ? Layout.Setup.pressedOpacity : 1)
            .contentShape(Rectangle())
            // The system's focus ring, shaped to the link.
            .flowFocusRing(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }
}

// MARK: - First run

/// Teaches the gesture before there's any history: hold the key, speak, release.
private struct FirstRunCard: View {
    let keyName: String

    @State private var isKeyDown = false
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var handsFreeTip: String? {
        switch model.settings.handsFreeShortcut {
        case .doubleTap: "Tip: double-tap \(keyName) to keep talking without holding it."
        case .controlOption: "Tip: press \(SetupKit.handsFreeName(model.settings)) to keep talking without holding a key."
        case .off: nil
        }
    }

    var body: some View {
        Card(padding: Spacing.xxxl) {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Your first dictation").eyebrowStyle()
                    Text("Hold, speak, release.")
                        .font(Typography.display)
                        .tracking(Tracking.display)
                        .foregroundStyle(Palette.ink)
                    Text("Click into any text field, like a message, an email or a doc, then:")
                        .font(Typography.body)
                        .foregroundStyle(Palette.inkSecondary)
                }

                HStack(alignment: .top, spacing: Spacing.xxl) {
                    step(number: 1, title: "Hold \(keyName)", detail: "Press and keep holding while you talk.") {
                        KeyCap(label: keyName, size: .large, isPressed: isKeyDown)
                    }
                    step(number: 2, title: "Speak", detail: "Talk naturally. Pauses and “um”s get tidied up.") {
                        // The logo's bars: your voice, in the app's own mark. Nothing is live
                        // here, so no spectrum.
                        BrandMark(height: Layout.Main.brandMarkLarge)
                    }
                    step(number: 3, title: "Release", detail: "Clean text lands right where your cursor was.") {
                        Image(systemName: "text.cursor")
                            .font(Typography.display)
                            .foregroundStyle(Palette.ink)
                    }
                }

                HStack(spacing: Spacing.m) {
                    // Primary once setup is done; until then "Continue Setup" is the primary.
                    if model.settings.hasCompletedOnboarding {
                        tryButton.buttonStyle(.flowPrimary)
                    } else {
                        tryButton.buttonStyle(.flowSecondary)
                    }
                    if let handsFreeTip {
                        Text(handsFreeTip)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
        }
        // Act out "hold" on the keycap, gently, while the card is on screen.
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Motion.demoKeyInterval)
                isKeyDown.toggle()
            }
        }
    }

    private var tryButton: some View {
        Button {
            model.controller.toggleRecording()
        } label: {
            Label("Try it hands-free", systemImage: "mic.fill")
        }
        .help("Start dictating without holding a key. Click Stop, or press \(keyName), when you're done.")
    }

    private func step<Visual: View>(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder visual: () -> Visual
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            visual()
                .frame(height: Layout.Main.firstRunVisualHeight, alignment: .bottomLeading)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text("\(number)")
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkTertiary)
                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(Palette.ink)
                }
                Text(detail)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
