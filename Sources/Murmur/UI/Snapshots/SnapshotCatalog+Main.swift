import MurmurKit
import SwiftUI

// Owned by the ui-main agent: main window screens with sample data.
extension SnapshotCatalog {
    static var main: [SnapshotRenderer.Shot] {
        let size = CGSize(width: 1040, height: 700)
        let records = SampleData.records()
        let sample = MainPreview(
            status: SampleData.readyStatus,
            stats: SampleData.stats(for: records),
            firstName: "Levi"
        )
        var firstRun = sample
        firstRun.stats = nil
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
        ]
    }

    private static func sidebars(records: [HistoryRecord]) -> some View {
        let ready = SampleData.readyStatus
        var noAccess = ready
        noAccess.accessibility = false
        noAccess.model = .downloading(0.42)
        var recording = ready
        recording.isRecording = true
        var failed = ready
        failed.model = .failed("The model files are damaged. Murmur will download them again.")
        return HStack(spacing: 0) {
            ForEach(Array([ready, noAccess, recording, failed].enumerated()), id: \.offset) { index, status in
                MainSidebar(status: status)
                    .environment(previewModel(records: records, section: index == 0 ? .home : .history))
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
