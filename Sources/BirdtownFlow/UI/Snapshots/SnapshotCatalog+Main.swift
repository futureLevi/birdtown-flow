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

        return [
            SnapshotRenderer.Shot("home", size: size) { window(.home, records: records, preview: sample) },
            SnapshotRenderer.Shot("home-empty", size: size) { window(.home, records: [], preview: firstRun) },
            SnapshotRenderer.Shot("history", size: size) { window(.history, records: records, preview: sample) },
            SnapshotRenderer.Shot("history-search", size: size) { window(.history, records: records, preview: search) },
            SnapshotRenderer.Shot("history-expanded-original", size: size) {
                window(.history, records: records, preview: original)
            },
            SnapshotRenderer.Shot("dictionary", size: size) { window(.dictionary, records: records, preview: sample) },
            SnapshotRenderer.Shot("snippets", size: size) { window(.snippets, records: records, preview: sample) },
            SnapshotRenderer.Shot("style", size: size) { window(.style, records: records, preview: sample) },
            // The sidebar column on its own: macOS 26 hosts it in a glass panel that offscreen
            // rendering can't capture, so it gets a shot of its own (with each status state).
            SnapshotRenderer.Shot("main-sidebar", size: CGSize(width: 4 * Layout.sidebarWidth, height: 520)) {
                sidebars(records: records)
            },
            // The toolbar never renders in window shots, so the Dictate pill (idle and live)
            // and the shared controls get a sheet of their own.
            SnapshotRenderer.Shot("main-components", size: CGSize(width: 760, height: 420)) {
                components(records: records)
            },
        ]
    }

    /// A fixed moment in the live orb's turn, so recording states render identically.
    private static let orbPhase: Double = 2.4

    private static func components(records: [HistoryRecord]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: Spacing.m) {
                DictateButton(isRecording: false) {}
                DictateButton(isRecording: true, orbPhase: orbPhase) {}
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
                StatTile(label: "Pace", value: 152, unit: "wpm", caption: "3.4× faster than typing")
            }
            SearchField(text: .constant("migration"), prompt: "Search words or apps")
                .frame(width: Layout.Main.searchFieldWidth)
        }
        .padding(Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
        .environment(previewModel(records: records, section: .home))
        .transaction { $0.disablesAnimations = true }
    }

    private static func sidebars(records: [HistoryRecord]) -> some View {
        let ready = SampleData.readyStatus
        var noAccess = ready
        noAccess.accessibility = false
        noAccess.model = .downloading(0.42)
        var recording = ready
        recording.isRecording = true
        var failed = ready
        failed.model = .failed("The model files are damaged. Birdtown Flow will download them again.")
        return HStack(spacing: 0) {
            ForEach(Array([ready, noAccess, recording, failed].enumerated()), id: \.offset) { index, status in
                MainSidebar(status: status)
                    .environment(previewModel(records: records, section: index == 0 ? .home : .history))
                    .environment(\.mainPreview, MainPreview(orbPhase: orbPhase))
                    .frame(width: Layout.sidebarWidth)
                    .background(Palette.sunken)
            }
        }
        .transaction { $0.disablesAnimations = true }
    }

    private static func previewModel(records: [HistoryRecord], section: SidebarSection) -> AppModel {
        let model = AppModel.preview(records: records)
        model.section = section
        return model
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
