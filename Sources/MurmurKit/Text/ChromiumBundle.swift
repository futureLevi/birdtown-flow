import Foundation

/// Recognizes apps built on Chromium (Electron, CEF, Chromium browsers) from what's in their
/// `Contents/Frameworks` folder, for apps not on `TextInjector`'s list by bundle ID.
///
/// These apps accept Accessibility writes and drop them, or don't build their AX tree until an
/// assistive app asks, so the focused text box can look like nothing at all. Typing into them
/// has to go through the clipboard and ⌘V.
///
/// Looking for "Electron Framework.framework" alone isn't enough: custom Electron builds can
/// rename it, and the ChatGPT app (`com.openai.codex`, Electron) slipped past that one check.
/// Electron apps also ship their multi-process helpers beside the framework, "<App> Helper
/// (Renderer).app", "(GPU)", "(Plugin)", which doesn't depend on the framework's name.
public enum ChromiumBundle {
    /// `entries` are the names in the app's `Contents/Frameworks` folder.
    public static func isChromiumBased(frameworkEntries entries: [String]) -> Bool {
        entries.contains { entry in
            frameworkNames.contains(entry)
                || helperSuffixes.contains { entry.hasSuffix($0) }
        }
    }

    private static let frameworkNames: Set<String> = [
        "Electron Framework.framework",
        "Chromium Embedded Framework.framework",
    ]

    private static let helperSuffixes = [
        "Helper (Renderer).app", "Helper (GPU).app", "Helper (Plugin).app",
    ]
}
