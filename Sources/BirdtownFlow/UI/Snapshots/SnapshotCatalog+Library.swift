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
            // Editing a linked snippet: the expansion is the link's text, the address under it.
            SnapshotRenderer.Shot("snippet-editor-link", size: CGSize(width: Layout.Main.sheetWidth, height: 640)) {
                snippetEditor(records: records)
            },
            // The panel's polish row sits below the preview, past the first screen, so these
            // render the whole page (as the Lab catalog does) rather than its first screen.
            // Polish on: the row names who polishes (Casual uses a Lab configuration here).
            SnapshotRenderer.Shot("style-polish-on", size: CGSize(width: size.width, height: styleFullHeight)) {
                libraryWindow(.style, records: records, preview: preview) { model in
                    model.settings.polishProvider = .appleIntelligence
                }
            },
            // Apps moved between categories: Notes added to Personal messages, Mail moved
            // there from Email, Safari added for every tab.
            SnapshotRenderer.Shot("style-apps-moved", size: CGSize(width: size.width, height: styleAppsHeight)) {
                libraryWindow(.style, records: records, preview: preview) { model in
                    model.settings.setCategory(.personal, forApp: "com.apple.Notes")
                    model.settings.setCategory(.personal, forApp: "com.apple.mail")
                    model.settings.setCategory(.personal, forApp: "com.apple.Safari")
                    model.settings.setCategory(.personal, forApp: "com.example.not-installed")
                }
            },
            // Polish off: the row reads "AI polish is off" with "Turn on AI polish".
            SnapshotRenderer.Shot("style-polish-off", size: CGSize(width: size.width, height: styleFullHeight)) {
                libraryWindow(.style, records: records, preview: preview) { model in
                    model.settings.polishProvider = .off
                }
            },
        ]
    }

    /// Tall enough for the Style page's header, category list, tone choices, preview and polish row.
    private static let styleFullHeight: CGFloat = 1_100
    /// Down to the bottom of the apps panel under the tone panel.
    private static let styleAppsHeight: CGFloat = 1_600

    /// The snippet sheet on the sample's linked snippet.
    private static func snippetEditor(records: [HistoryRecord]) -> some View {
        let model = AppModel.preview(records: records)
        let linked = model.snippets.snippets.first { $0.linked != nil }
        return SnippetEditorSheet(original: linked, onSave: { _ in }, onDelete: {})
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Palette.surface)
            .environment(model)
            .transaction { $0.disablesAnimations = true }
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
