import SwiftUI

// PLACEHOLDER — owned by the ui-setup agent.

/// The menu bar extra's window.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading) {
            Button("Open Murmur") { model.show(.home) }
            Button("Quit Murmur") { NSApp.terminate(nil) }
        }
        .padding()
    }
}

/// The menu bar icon.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(systemName: "waveform")
    }
}
