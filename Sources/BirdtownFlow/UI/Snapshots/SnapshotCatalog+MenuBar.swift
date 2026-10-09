import SwiftUI

// Owned by the menu bar: the warning states, each with the row that fixes it. The settled
// states (ready, downloading, listening…) are in `SnapshotCatalog+Setup`.
extension SnapshotCatalog {
    static var menuBarWarnings: [SnapshotRenderer.Shot] {
        // A fix row adds up to two lines; leave room so nothing clips at the bottom.
        let size = CGSize(width: Layout.Setup.menuBarWidth, height: 540)
        let model = AppModel.setupPreview { $0.hasCompletedOnboarding = true }

        var microphone = SetupPreview()
        microphone.microphone = .denied

        // The grant lapsed after an update: the switch still shows on in System Settings.
        var accessibility = SetupPreview()
        accessibility.accessibility = false
        accessibility.hotkeyActive = false

        // Access is on but the tap still can't be created: what the app bundle offers.
        var shortcut = SetupPreview()
        shortcut.hotkeyActive = false
        shortcut.canRelaunch = true

        var modelMissing = SetupPreview()
        modelMissing.modelState = .notDownloaded

        var modelFailed = SetupPreview()
        modelFailed.modelState = .failed("The Internet connection appears to be offline.")

        func shot(_ name: String, _ facts: SetupPreview) -> SnapshotRenderer.Shot {
            SnapshotRenderer.Shot("setup-menubar-\(name)", size: size) {
                MenuBarContent()
                    .environment(model)
                    .environment(\.setupPreview, facts)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Palette.canvas)
            }
        }
        return [
            shot("fix-microphone", microphone),
            shot("fix-accessibility", accessibility),
            shot("fix-shortcut", shortcut),
            shot("fix-model-missing", modelMissing),
            shot("fix-model-failed", modelFailed),
        ]
    }
}
