import MurmurKit
import SwiftUI

// Owned by the ui-main agent: main window screens with sample data.
extension SnapshotCatalog {
    static var main: [SnapshotRenderer.Shot] {
        let size = CGSize(width: 1040, height: 700)
        let records = SampleData.records()
        let sample = MainPreview(status: SampleData.readyStatus, firstName: "Levi", orbPhase: Self.orbPhase)
        var firstRun = sample
        firstRun.status?.model = .downloading(0.42)
        var search = sample
        search.historyQuery = "migration"
        var original = sample
        original.originalRecordID = records.first { !$0.corrections.isEmpty }?.id
        // Only what the engine heard says "whisper"; the text says "Wispr".
        var heardSearch = sample
        heardSearch.historyQuery = "whisper"
        // The hit is at the end of a long email, past the collapsed preview.
        var excerptSearch = sample
        excerptSearch.historyQuery = "afternoon"
        // Halfway through a Shimmer sweep, the band of light over the loudest syllables. (The
        // CI runner has Reduce Motion on, so the other shots show the hero at rest.)
        var shimmer = sample
        shimmer.heroSweepPhase = VoiceprintMotion.sweepDuration / 2
        var paused = sample
        paused.status?.hotkeyActive = false
        var selected = sample
        selected.historySelection = Array(records.filter(\.hasText).prefix(3).map(\.id))

        return [
            SnapshotRenderer.Shot("home", size: size) { window(.home, records: records, preview: sample) },
            SnapshotRenderer.Shot("home-shimmer", size: size) { window(.home, records: records, preview: shimmer) },
            SnapshotRenderer.Shot("home-empty", size: size) { window(.home, records: [], preview: firstRun) },
            SnapshotRenderer.Shot("history", size: size) { window(.history, records: records, preview: sample) },
            SnapshotRenderer.Shot("history-search", size: size) { window(.history, records: records, preview: search) },
            SnapshotRenderer.Shot("history-expanded-original", size: size) {
                window(.history, records: records, preview: original)
            },
            SnapshotRenderer.Shot("history-search-heard", size: size) {
                window(.history, records: records, preview: heardSearch)
            },
            SnapshotRenderer.Shot("history-search-excerpt", size: size) {
                window(.history, records: records, preview: excerptSearch)
            },
            // ⌘-clicked or ⌘A: the bar that says how many and offers Copy and Delete.
            SnapshotRenderer.Shot("history-selection", size: size) {
                window(.history, records: records, preview: selected)
            },
            // The Timings view: every row says how long each step took, one with Original open.
            SnapshotRenderer.Shot("history-timings", size: size) {
                historyTimings(records: records, preview: original)
            },
            // A delete from Recent, still undoable: Home shows the same toast as History.
            SnapshotRenderer.Shot("home-undo-delete", size: size) {
                undoDelete(.home, records: records, preview: sample)
            },
            SnapshotRenderer.Shot("history-undo-delete", size: size) {
                undoDelete(.history, records: records, preview: sample)
            },
            // Transcribe Again on dictations that worked: one in flight, one whose new attempt
            // failed (old text kept), one replaced (Restore earlier text).
            SnapshotRenderer.Shot("history-transcribe-again", size: size) {
                transcribeAgain(records: records, preview: sample)
            },
            SnapshotRenderer.Shot("dictionary", size: size) { window(.dictionary, records: records, preview: sample) },
            SnapshotRenderer.Shot("snippets", size: size) { window(.snippets, records: records, preview: sample) },
            SnapshotRenderer.Shot("style", size: size) { window(.style, records: records, preview: sample) },
            // The Lab as it opens, and the whole page: editor, test text and results.
            SnapshotRenderer.Shot("lab", size: size) { lab(records: records, preview: sample) },
            SnapshotRenderer.Shot("lab-full", size: CGSize(width: size.width, height: 2_150)) {
                lab(records: records, preview: sample)
            },
            // Every configuration deleted: the Lab invites a new one.
            SnapshotRenderer.Shot("lab-empty", size: size) { labEmpty(records: records, preview: sample) },
            // The sidebar tucked away: Show sidebar beside the traffic lights.
            SnapshotRenderer.Shot("main-sidebar-hidden", size: size) {
                sidebarHidden(records: records, preview: sample)
            },
            // The shortcut lost its event tap: Home says so, now the sidebar has no footer.
            SnapshotRenderer.Shot("home-shortcut-paused", size: size) {
                window(.home, records: records, preview: paused)
            },
            // Settings as a modal over the window, on General and on Text & AI.
            SnapshotRenderer.Shot("settings-modal", size: size) {
                settingsModal(.general, records: records, preview: sample)
            },
            SnapshotRenderer.Shot("settings-modal-text", size: size) {
                settingsModal(.text, records: records, preview: sample)
            },
            // The window at its smallest: the card shrinks and its pane scrolls.
            SnapshotRenderer.Shot(
                "settings-modal-small",
                size: CGSize(width: Layout.windowMinWidth, height: Layout.windowMinHeight)
            ) {
                settingsModal(.audio, records: records, preview: sample)
            },
            // The shared controls, on a sheet of their own.
            SnapshotRenderer.Shot("main-components", size: CGSize(width: 760, height: 400)) {
                components(records: records)
            },
        ] + library(size: size, records: records, preview: sample)  // SnapshotCatalog+Library.swift
    }

    /// A fixed moment in the live orb's turn, so recording states render identically.
    private static let orbPhase: Double = 2.4

    private static func components(records: [HistoryRecord]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: Spacing.m) {
                Button("Continue Setup") {}.buttonStyle(.flowPrimary).controlSize(.small)
                Button("Open Settings") {}.buttonStyle(.flowSecondary)
                Button("All history") {}.buttonStyle(.flowGhost)
            }
            HStack(spacing: Spacing.s) {
                FilterChip(title: "All", isSelected: true) {}
                FilterChip(title: "Failed", symbol: "exclamationmark.triangle", count: 2, isSelected: false) {}
                FilterChip(title: "Polished", symbol: "sparkles", count: 6, isSelected: false) {}
                Badge(text: "Polished · Claude", symbol: "sparkles")
                Badge(text: "Chosen", tone: .accent)
                Badge(text: "Failed", symbol: "exclamationmark.triangle.fill", tone: .danger)
            }
            HStack(alignment: .top, spacing: Spacing.m) {
                Card(isSelected: true) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Selected card").font(Typography.headline).foregroundStyle(Palette.ink)
                        Text("Signal blue ring over a soft wash.").font(Typography.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack(spacing: Spacing.s) {
                            Text("Hold").font(Typography.callout).foregroundStyle(Palette.inkSecondary)
                            KeyCap(label: "fn")
                            StatusDot(color: Palette.success)
                            StatusDot(color: Palette.danger)
                        }
                        SpectrumProgressBar(progress: 0.42)
                    }
                }
                StatTile(label: "Pace", value: 152, unit: "wpm", caption: "3.4× faster than typing",
                         symbol: "gauge.with.dots.needle.67percent", tone: .green)
            }
            .fixedSize(horizontal: false, vertical: true)
            SearchField(text: .constant("migration"), prompt: "Search words or apps")
                .frame(width: Layout.Main.searchFieldWidth)
        }
        .padding(Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
        .environment(previewModel(records: records, section: .home))
        .transaction { $0.disablesAnimations = true }
    }

    /// The Lab mid-session: a draft open, three styles assigned and four results.
    private static func lab(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = AppModel.preview(records: records, lab: SampleData.labState)
        model.section = .lab
        model.settings.polishProvider = .claudeCode
        model.bench.preview(selected: SampleData.labDraft.id, draft: SampleData.labDraft, runs: SampleData.labRuns())
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    /// The Lab with no configurations left.
    private static func labEmpty(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = AppModel.preview(records: records, lab: PolishLabState())
        model.section = .lab
        model.settings.polishProvider = .claudeCode
        model.bench.preview(selected: nil, draft: nil, runs: [])
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    /// History with the sidebar hidden.
    private static func sidebarHidden(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = previewModel(records: records, section: .history)
        model.sidebarHidden = true
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    private static func previewModel(records: [HistoryRecord], section: SidebarSection) -> AppModel {
        let model = AppModel.preview(records: records)
        model.section = section
        return model
    }

    /// `section` with the newest dictation that has text just deleted, inside its undo window.
    private static func undoDelete(_ section: SidebarSection, records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = previewModel(records: records, section: section)
        if let first = records.sorted(by: { $0.createdAt > $1.createdAt }).first(where: \.hasText) {
            // Every shot is built before any renders: hold the undo window open past them all.
            model.historyDeletion.delete([first.id], window: .seconds(3600))
        }
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    /// History with the Timings view on.
    private static func historyTimings(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = previewModel(records: records, section: .history)
        model.settings.historyShowsTimings = true
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    /// History with the first three dictations that have text mid-"Transcribe Again", kept
    /// after a failed attempt, and replaced.
    private static func transcribeAgain(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = previewModel(records: records, section: .history)
        let tracker = RetryTracker()
        let good = records.sorted(by: { $0.createdAt > $1.createdAt }).filter(Retranscription.hasGoodText)
        if good.count >= 3 {
            var earlier = good[2]
            earlier.finalText = "An earlier attempt at this dictation."
            tracker.preview(
                inFlight: [good[0].id],
                replaced: [good[2].id: earlier],
                keptReasons: [good[1].id: "No speech was heard this time."]
            )
        }
        model.retries = tracker
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    /// Home with Settings open over it on `tab`. Settings' panes read faked service state
    /// (permissions, model, login item) so the shot doesn't depend on the CI machine.
    private static func settingsModal(_ tab: SettingsTab, records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = previewModel(records: records, section: .home)
        model.settingsTab = tab
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .environment(\.setupPreview, SetupPreview())
            .transaction { $0.disablesAnimations = true }
    }

    /// The main window on `section`, backed by an in-memory model. Animations are disabled
    /// so count-ups and fades are captured at rest.
    private static func window(_ section: SidebarSection, records: [HistoryRecord], preview: MainPreview) -> some View {
        MainView()
            .environment(previewModel(records: records, section: section))
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }
}
