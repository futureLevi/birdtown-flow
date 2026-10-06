import SwiftUI

// PLACEHOLDER — owned by the ui-setup agent.

/// The Settings window (⌘,).
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("Settings")
            .frame(width: Layout.settingsWidth, height: 400)
    }
}
