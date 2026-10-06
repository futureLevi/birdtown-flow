import AppKit
import MurmurKit
import SwiftUI

/// Home: a greeting, what needs fixing, the week in numbers, and the last few dictations.
struct HomeView: View {
    let status: SystemStatus

    @Environment(AppModel.self) private var model
    @Environment(\.mainPreview) private var preview
    @State private var player = AudioPlayback()

    var body: some View {
        let records = model.history.records
        let stats = DictationStats.compute(from: records)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header(stats: stats, isFirstRun: records.isEmpty)
                HomeBanners(status: status)
                if records.isEmpty {
                    FirstRunCard(keyName: status.pushToTalkKey, isSetupComplete: model.settings.hasCompletedOnboarding)
                } else {
                    tiles(stats: stats, records: records)
                    recent(Array(records.prefix(Layout.Main.recentCount)))
                }
            }
            .pageLayout()
        }
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
                    Text("Murmur turns your voice into clean text, wherever you're typing.")
                } else if stats.wordsThisWeek > 0 {
                    Text("You've spoken \(stats.wordsThisWeek.formatted()) words into your Mac this week.")
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
                caption: stats.dictationCount == 1 ? "From 1 dictation" : "From \(stats.dictationCount) dictations"
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
                caption: "vs. typing at \(DictationStats.typingWPM) wpm"
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
                .buttonStyle(.murmurGhost)
                .controlSize(.small)
            }
            VStack(spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        RowDivider(leadingInset: HistoryRow.textInset)
                    }
                    HistoryRow(record: record, player: player) {
                        if player.isPlaying(record.id) { player.stop() }
                        model.history.delete(ids: [record.id])
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

    var body: some View {
        VStack(spacing: Spacing.s) {
            // Until setup is finished, its banner stands in for the permission banners below:
            // setup walks through the same grants, in order, with explanations.
            if !model.settings.hasCompletedOnboarding {
                Banner(
                    symbol: "checklist",
                    title: "Finish setting up Murmur",
                    message: "Two minutes: permissions, your shortcut, and a first dictation.",
                    tone: .info
                ) {
                    Button("Continue Setup") { OnboardingWindowController.shared.show(model: model) }
                        .buttonStyle(.murmurPrimary)
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
                    title: "Murmur can't hear you yet",
                    message: "Allow microphone access so Murmur can listen while you hold \(status.pushToTalkKey).",
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
                    .buttonStyle(.murmurSecondary)
                    .controlSize(.small)
                }
            }
            if !status.accessibility {
                Banner(
                    symbol: "keyboard",
                    title: "Allow Accessibility to use \(status.pushToTalkKey)",
                    message: "Murmur needs it to notice your shortcut and to type into other apps.",
                    tone: .warning
                ) {
                    Button("Open Settings") { Permissions.openAccessibilitySettings() }
                        .buttonStyle(.murmurSecondary)
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
                    ProgressView(value: progress ?? 0)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .tint(Palette.ink)
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
                    .buttonStyle(.murmurSecondary)
                    .controlSize(.small)
            }
        case .failed(let message):
            Banner(
                symbol: "exclamationmark.triangle.fill",
                title: "The speech model didn't load",
                message: message,
                tone: .danger
            ) {
                Button("Try Again") { Task { await model.models.prepare() } }
                    .buttonStyle(.murmurSecondary)
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
    /// Until setup is done the setup banner carries the one Ember button; trying dictation
    /// before permissions are granted would only fail.
    let isSetupComplete: Bool

    @State private var isKeyDown = false
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Card(padding: Spacing.xxxl) {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Your first dictation").eyebrowStyle()
                    Text("Hold, speak, release.")
                        .font(Typography.display)
                        .tracking(Tracking.display)
                        .foregroundStyle(Palette.ink)
                    Text("Click into any text field — a message, an email, a doc — then:")
                        .font(Typography.body)
                        .foregroundStyle(Palette.inkSecondary)
                }

                HStack(alignment: .top, spacing: Spacing.xxl) {
                    step(number: 1, title: "Hold \(keyName)", detail: "Press and keep holding while you talk.") {
                        KeyCap(label: keyName, size: .large, isPressed: isKeyDown)
                    }
                    step(number: 2, title: "Speak", detail: "Talk naturally. Pauses and “um”s get tidied up.") {
                        DemoWaveform()
                    }
                    step(number: 3, title: "Release", detail: "Clean text lands right where your cursor was.") {
                        Image(systemName: "text.cursor")
                            .font(Typography.display)
                            .foregroundStyle(Palette.ink)
                    }
                }

                HStack(spacing: Spacing.m) {
                    if isSetupComplete {
                        tryButton.buttonStyle(.murmurPrimary)
                    } else {
                        tryButton.buttonStyle(.murmurSecondary)
                    }
                    Text("Tip: double-tap \(keyName) to keep talking without holding it.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkTertiary)
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

/// A still waveform in Ember: the mark Murmur shows while it's listening.
private struct DemoWaveform: View {
    private static let levels: [CGFloat] = [0.35, 0.6, 0.95, 0.7, 0.45, 0.85, 1, 0.55, 0.3, 0.6, 0.4]

    var body: some View {
        HStack(alignment: .center, spacing: Layout.HUD.barSpacing) {
            ForEach(Array(Self.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Palette.ember)
                    .frame(width: Layout.HUD.barWidth,
                           height: max(Layout.HUD.barMinHeight, Layout.Main.keyCapHeightLarge * level))
            }
        }
        .frame(height: Layout.Main.keyCapHeightLarge)
        .accessibilityHidden(true)
    }
}
