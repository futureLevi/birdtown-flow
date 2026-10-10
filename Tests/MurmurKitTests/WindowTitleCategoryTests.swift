import Testing
@testable import MurmurKit

/// Polish is made ready while the person talks, for the instructions their dictation's category
/// will get. Key-down reads the frontmost app without its window title; these say when that is
/// already the category the dictation uses, and what the title makes of it when it isn't.
@Suite("Category from the window title")
struct WindowTitleCategoryTests {
    @Test("Browsers and web apps wait for the title", arguments: [
        "com.google.Chrome",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.google.Chrome.app.abcdefghijklmnop",
        "com.apple.Safari.WebApp.5A1B2C3D",
        "com.microsoft.edgemac.app.qrstuvwxyz",
    ])
    func browsers(bundleID: String) {
        #expect(AppCategoryResolver.categoryDependsOnTitle(bundleID: bundleID))
    }

    @Test("Other apps are categorized at key-down", arguments: [
        "com.apple.mail",
        "com.tinyspeck.slackmacgap",
        "com.apple.MobileSMS",
        "com.apple.TextEdit",
        "com.microsoft.VSCode",
        "",
    ])
    func otherApps(bundleID: String) {
        #expect(!AppCategoryResolver.categoryDependsOnTitle(bundleID: bundleID))
    }

    @Test("No app, no title to wait for")
    func noApp() {
        #expect(!AppCategoryResolver.categoryDependsOnTitle(bundleID: nil))
    }

    @Test("Where the title doesn't decide, it never changes the category")
    func finalWithoutTitle() {
        let titles = [
            "Inbox (3) - levi@birdtown.ai - Gmail",
            "general (Channel) - Birdtown - Slack",
            "(3) WhatsApp",
            "Untitled",
        ]
        let native = AppCategoryResolver.personalApps
            .union(AppCategoryResolver.workApps)
            .union(AppCategoryResolver.emailApps)
        var apps: [String?] = ["com.apple.TextEdit", "com.apple.Notes", "", nil]
        for bundleID in native.sorted() { apps.append(bundleID) }
        for bundleID in apps {
            #expect(!AppCategoryResolver.categoryDependsOnTitle(bundleID: bundleID))
            let atKeyDown = AppCategoryResolver.category(bundleID: bundleID, windowTitle: nil)
            for title in titles {
                #expect(AppCategoryResolver.category(bundleID: bundleID, windowTitle: title) == atKeyDown)
            }
        }
    }

    @Test("A browser dictation into Gmail gets polish ready for email")
    func gmailInBrowser() {
        let bundleID = "com.google.Chrome"
        let quick = AppContext(
            bundleID: bundleID, appName: "Google Chrome",
            category: AppCategoryResolver.category(bundleID: bundleID, windowTitle: nil))
        // Key-down's guess: a session started for it would be thrown away at key-up…
        #expect(quick.category == .other)
        #expect(AppCategoryResolver.categoryDependsOnTitle(bundleID: quick.bundleID))
        // …so polish waits for the title, and gets ready for email.
        let refined = quick.withWindowTitle("Inbox (3) - levi@birdtown.ai - Gmail")
        #expect(refined.category == .email)
        #expect(refined.windowTitle == "Inbox (3) - levi@birdtown.ai - Gmail")
        #expect(refined.bundleID == quick.bundleID)
        #expect(refined.appName == quick.appName)
    }

    @Test("A title that can't be read leaves the context as it was")
    func unreadableTitle() {
        let quick = AppContext(bundleID: "com.google.Chrome", appName: "Google Chrome", category: .other)
        #expect(quick.withWindowTitle(nil) == quick)
        #expect(quick.withWindowTitle("") == quick)
    }

    @Test("A native app keeps its category whatever its title says")
    func nativeAppTitle() {
        let mail = AppContext(bundleID: "com.apple.mail", appName: "Mail", category: .email)
        let titled = mail.withWindowTitle("general (Channel) - Birdtown - Slack")
        #expect(titled.category == .email)
        #expect(titled.windowTitle == "general (Channel) - Birdtown - Slack")
    }
}
