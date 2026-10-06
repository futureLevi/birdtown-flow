import SwiftUI

// Owned by the ui-main agent: main window screens with sample data.
extension SnapshotCatalog {
    static var main: [SnapshotRenderer.Shot] {
        [
            SnapshotRenderer.Shot("main-placeholder", size: CGSize(width: 1040, height: 700)) {
                MainView().environment(AppModel.shared)
            },
        ]
    }
}
