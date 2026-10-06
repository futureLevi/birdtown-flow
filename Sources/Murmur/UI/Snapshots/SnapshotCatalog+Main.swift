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
        ]
    }

    /// The main window on `section`, backed by an in-memory model. Animations are disabled
    /// so count-ups and fades are captured at rest.
    private static func window(_ section: SidebarSection, records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = AppModel.preview(records: records)
        model.section = section
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }
}
