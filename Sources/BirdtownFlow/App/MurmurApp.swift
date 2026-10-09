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
        // Settings is a modal in the main window, not a Settings scene: ⌘, opens the window
        // (reopening it if it was closed) with Settings over it.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppModel.shared.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        // ⌘O brings up the main window from any of the app's windows, even after it was closed.
        CommandGroup(replacing: .newItem) {
            Button("Open Birdtown Flow") {
                openWindow(id: "main")
                NSApp.activate()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(after: .pasteboard) {
            // Shows ⌃⌥V only while that is the paste-last shortcut. A recorded chord is still
            // honoured by the global hot key; the menu just shows no key for it.
            Button("Paste Last Dictation") { AppModel.shared.controller.pasteLast() }
                .keyboardShortcut(Self.pasteLastMenuShortcut)
            // Hands-free from the keyboard while the app is in front, now that the toolbar
            // has no Dictate button.
            Button("Start or Stop Dictating") { AppModel.shared.controller.toggleRecording() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }

    @MainActor
    private static var pasteLastMenuShortcut: KeyboardShortcut? {
        let settings = Settings.shared
        guard settings.pasteLastShortcutEnabled, settings.pasteLastShortcut == .pasteLastDefault else { return nil }
        return KeyboardShortcut("v", modifiers: [.control, .option])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Writing to a pipe whose reader has gone (a Claude Code session that just exited)
        // must fail with an error, not kill the app with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
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
            } else if Self.launchedAsLoginItem, model.controller.isHotkeyActive,
                      model.permissions.microphone {
                // Settings promises a quiet start at login: don't keep the main window (and
                // its History stats) alive while the model loads. Reopen, ⌘O and the menu bar
                // bring it back. If the window isn't up yet or the flag isn't readable,
                // launch behaves as before. A broken setup (a lost Accessibility grant after a
                // rebuild, no microphone) keeps the window, the only place that says so.
                Task { @MainActor in
                    NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.close()
                }
            }
        }
    }

    /// Whether macOS opened the app as a login item. Only meaningful while the launch's
    /// open-application event is being handled, i.e. during `applicationDidFinishLaunching`.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication),
              let property = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))
        else { return false }
        return property.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
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
        ClaudeCodePolisher.shutDown()
    }
}
