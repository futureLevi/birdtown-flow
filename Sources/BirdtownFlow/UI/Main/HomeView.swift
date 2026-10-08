import AppKit
import MurmurKit
import SwiftUI

/// Home: a greeting, what needs fixing, the week in numbers, and the last few dictations.
struct HomeView: View {
    let status: SystemStatus

    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player = AudioPlayback()
    @State private var pendingStats = ViewMemo<PendingStatsKey, DictationStats>()

    /// What Home's numbers depend on while a delete can still be undone.
    private struct PendingStatsKey: Equatable {
        var records: [HistoryRecord]
        var pending: Set<UUID>
    }

    var body: some View {
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
        // The same array, uncopied, when nothing is pending.
        let visible = model.historyDeletion.visible(records)
        let recentRecords = Array(visible.prefix(Layout.Main.recentCount))
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header(stats: stats, isFirstRun: records.isEmpty)
                // An empty banner stack would still take a slot and double the gap.
                if HomeBanners.isVisible(status: status, hasCompletedOnboarding: model.settings.hasCompletedOnboarding) {
                    HomeBanners(status: status)
                }
                if records.isEmpty {
                    FirstRunCard(keyName: status.pushToTalkKey)
                } else {
                    tiles(stats: stats, records: visible)
                    recent(recentRecords)
                }
            }
            .pageLayout()
        }
        // Room to scroll the last row clear of the undo toast while it's up.
        .contentMargins(.bottom, pending.isEmpty ? 0 : Layout.Main.floatingBarClearance, for: .scrollContent)
        // The same Undo as History's, so a delete from Recent can be taken back (⌘Z too).
        .overlay(alignment: .bottom) { HistoryUndoToast() }
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: model.historyDeletion.pending)
        .onDisappear { player.stop() }
    }

    private func header(stats: DictationStats, isFirstRun: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Self.greeting(name: preview.firstName ?? Self.firstName))
                .font(Typography.display)
                .tracking(Tracking.display)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Group {
                if isFirstRun {
                    Text("Birdtown Flow turns your voice into clean text, wherever you're typing.")
                } else if stats.wordsThisWeek > 0 {
                    // The week's word count is the first tile below; don't say it twice.
                    Text("Hold \(status.pushToTalkKey) anywhere to dictate.")
                } else {
                    Text("Ready when you are.")
                }
            }
            .font(Typography.body)
            .foregroundStyle(Palette.inkSecondary)
        }
    }

    private func tiles(stats: DictationStats, records: [HistoryRecord]) -> some View {
        let dictatedToday = records.contains { Calendar.current.isDateInToday($0.createdAt) }
        let speedup = Double(stats.averageWPM) / Double(DictationStats.typingWPM)
        return HStack(spacing: Spacing.m) {
            StatTile(
                label: "This week",
                value: stats.wordsThisWeek,
                unit: "words",
                caption: "\(stats.totalWords.formatted()) all time"
            )
            StatTile(
                label: "Pace",
                value: stats.averageWPM,
                unit: "wpm",
                caption: stats.averageWPM > 0
                    ? "\(speedup.formatted(.number.precision(.fractionLength(1))))× faster than typing"
                    : "Measured on longer dictations"
            )
            StatTile(
                label: "Streak",
                value: stats.dayStreak,
                unit: stats.dayStreak == 1 ? "day" : "days",
                caption: dictatedToday ? "Today counts" : "Dictate today to keep it"
            )
            StatTile(
                label: "Time saved",
                value: stats.minutesSaved,
                unit: "min",
                // Saved time is all-time (unlike the weekly tile), so the caption says so.
                caption: "All time, vs. typing"
            )
        }
    }

    private func recent(_ records: [HistoryRecord]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Recent") {
                Button {
                    model.section = .history
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Text("All history")
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                    }
                }
                .buttonStyle(.flowGhost)
                .controlSize(.small)
            }
            VStack(spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        RowDivider(leadingInset: HistoryRow.textInset)
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
    }

    // MARK: - Greeting

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

// MARK: - Banners

/// Missing permissions and model trouble, each with the fix one click away.
private struct HomeBanners: View {
    let status: SystemStatus
    @Environment(AppModel.self) private var model

    /// Whether any banner below would show; keep in step with `body`.
    static func isVisible(status: SystemStatus, hasCompletedOnboarding: Bool) -> Bool {
        if !hasCompletedOnboarding || !status.microphone || !status.accessibility { return true }
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
