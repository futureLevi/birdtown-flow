import Testing
@testable import MurmurKit

@Suite("ChromiumBundle")
struct ChromiumBundleTests {
    @Test("Recognizes Electron, CEF and renamed Electron builds", arguments: [
        // Stock Electron
        ["Electron Framework.framework", "Mantle.framework", "Slack Helper (Renderer).app"],
        // Electron with its framework renamed: the helpers still give it away
        ["ChatGPT Framework.framework", "ChatGPT Helper.app", "ChatGPT Helper (GPU).app",
         "ChatGPT Helper (Renderer).app", "Sparkle.framework"],
        ["Helper (Plugin).app"],
        // Chromium Embedded Framework (Spotify and others)
        ["Chromium Embedded Framework.framework", "Spotify Helper.app"],
    ])
    func chromium(entries: [String]) {
        #expect(ChromiumBundle.isChromiumBased(frameworkEntries: entries))
    }

    @Test("Leaves native apps alone", arguments: [
        [String](),
        ["Sparkle.framework"],
        ["Sparkle.framework", "Updater Helper.app", "libswiftCore.dylib"],
        // A native app's own framework named like Electron's isn't enough on its own
        ["Birdtown Framework.framework"],
    ])
    func native(entries: [String]) {
        #expect(!ChromiumBundle.isChromiumBased(frameworkEntries: entries))
    }
}
