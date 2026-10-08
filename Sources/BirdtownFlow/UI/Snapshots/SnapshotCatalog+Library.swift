import MurmurDictionary
import MurmurKit
import SwiftUI

// Owned by the library area (Dictionary, Snippets, Style): states the main catalog's plain
// page shots don't reach. Registered from `SnapshotCatalog.main`.
extension SnapshotCatalog {
    static func library(size: CGSize, records: [HistoryRecord], preview: MainPreview) -> [SnapshotRenderer.Shot] {
        [
            // A replacement just deleted: hidden from the list, with Undo (⌘Z) at the bottom.
            SnapshotRenderer.Shot("dictionary-undo", size: size) {
                libraryWindow(.dictionary, records: records, preview: preview) { model in
                    if let entry = model.dictionary.entries.first(where: { $0.kind == .correction }) {
                        model.dictionary.delete(ids: [entry.id], undoWindow: .seconds(3_600))
                    }
                }
            },
            // A snippet just deleted, waiting out its undo window.
            SnapshotRenderer.Shot("snippets-undo", size: size) {
                libraryWindow(.snippets, records: records, preview: preview) { model in
                    if let snippet = model.snippets.snippets.dropFirst().first {
                        model.snippets.delete(ids: [snippet.id], undoWindow: .seconds(3_600))
                    }
                }
            },
            // Polish on: the card names the provider and its button reads "Text & AI Settings…".
            SnapshotRenderer.Shot("style-polish-on", size: size) {
                libraryWindow(.style, records: records, preview: preview) { model in
                    model.settings.polishProvider = .appleIntelligence
                }
            },
        ]
    }

    /// The main window on `section` over an in-memory model that `prepare` puts in a state.
    private static func libraryWindow(
        _ section: SidebarSection,
        records: [HistoryRecord],
        preview: MainPreview,
        prepare: (AppModel) -> Void
    ) -> some View {
        let model = AppModel.preview(records: records)
        model.section = section
        prepare(model)
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }
}
