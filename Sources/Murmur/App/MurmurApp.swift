import AppKit
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Murmur", id: "main") {
            MainView()
                .environment(AppModel.shared)
                .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
        }
        .defaultSize(width: Layout.windowIdealWidth, height: Layout.windowIdealHeight)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { MurmurCommands() }

        Settings {
            SettingsView()
                .environment(AppModel.shared)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(AppModel.shared)
        } label: {
            MenuBarLabel()
                .environment(AppModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

/// App-menu additions.
struct MurmurCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Paste Last Dictation") { AppModel.shared.controller.pasteLast() }
                .keyboardShortcut("v", modifiers: [.control, .option])
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            // `Murmur --render-snapshots <dir>` renders every registered screen to PNGs and
            // exits. CI uses it so the UI can be reviewed without a person at a Mac.
            let args = CommandLine.arguments
            if let index = args.firstIndex(of: "--render-snapshots") {
                let path = index + 1 < args.count ? args[index + 1] : "snapshots"
                Task { @MainActor in
                    await SnapshotRenderer.run(to: URL(fileURLWithPath: path))
                    exit(0)
                }
                return
            }

            let model = AppModel.shared
            model.start()
            HUDController.shared.attach(to: model)
            if !model.settings.hasCompletedOnboarding {
                OnboardingWindowController.shared.show(model: model)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppModel.shared.show(AppModel.shared.section)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.history.flush()
    }
}
