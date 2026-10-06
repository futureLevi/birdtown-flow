import AppKit
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Birdtown Flow", id: "main") {
            MainView()
                .environment(AppModel.shared)
                .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
        }
        .defaultSize(width: Layout.windowIdealWidth, height: Layout.windowIdealHeight)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { MurmurCommands() }

        SwiftUI.Settings {
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // ⌘O brings up the main window from any of the app's windows, even after it was closed.
        CommandGroup(replacing: .newItem) {
            Button("Open Birdtown Flow") {
                openWindow(id: "main")
                NSApp.activate()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(after: .pasteboard) {
            Button("Paste Last Dictation") { AppModel.shared.controller.pasteLast() }
                .keyboardShortcut("v", modifiers: [.control, .option])
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before any window is built, so nothing draws first in the wrong appearance.
        Settings.shared.appearance.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            // `BirdtownFlow --render-snapshots <dir>` renders every registered screen to PNGs and
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

            // `BirdtownFlow --export-icon <AppIcon.iconset> [preview.png]` renders the icon set.
            if let index = args.firstIndex(of: "--export-icon") {
                let iconset = index + 1 < args.count ? args[index + 1] : "AppIcon.iconset"
                let preview = index + 2 < args.count ? URL(fileURLWithPath: args[index + 2]) : nil
                exit(IconExporter.run(iconset: URL(fileURLWithPath: iconset), preview: preview))
            }

            // `BirdtownFlow --transcribe <file.wav> [engine]` is the speech smoke test CI runs.
            if let index = args.firstIndex(of: "--transcribe") {
                let path = index + 1 < args.count ? args[index + 1] : ""
                let engine = index + 2 < args.count ? args[index + 2] : nil
                Task { @MainActor in
                    let code = await SpeechSmokeTest.run(file: URL(fileURLWithPath: path), engine: engine)
                    exit(code)
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
