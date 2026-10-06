import SwiftUI

// PLACEHOLDER — owned by the ui-main agent.

/// The main window: sidebar + detail.
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("Murmur")
            .font(Typography.display)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
    }
}
