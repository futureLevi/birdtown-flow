import Testing
@testable import MurmurKit

/// The Style page lets the person put any app in any category. Their choice wins over the
/// built-in lists and over a browser's window title.
@Suite("App category overrides")
struct AppCategoryOverrideTests {
    @Test("A chosen category wins over the built-in list")
    func overridesList() {
        let overrides: [String: AppCategory] = ["com.tinyspeck.slackmacgap": .personal]
        #expect(AppCategoryResolver.category(
            bundleID: "com.tinyspeck.slackmacgap", windowTitle: nil, overrides: overrides) == .personal)
        // Other apps are untouched.
        #expect(AppCategoryResolver.category(
            bundleID: "com.hnc.Discord", windowTitle: nil, overrides: overrides) == .work)
    }

    @Test("An unlisted app can join a category")
    func unlistedApp() {
        let overrides: [String: AppCategory] = ["com.apple.Notes": .work]
        #expect(AppCategoryResolver.category(bundleID: "com.apple.Notes", windowTitle: "Gmail", overrides: overrides) == .work)
        #expect(!AppCategoryResolver.categoryDependsOnTitle(bundleID: "com.apple.Notes", overrides: overrides))
    }

    @Test("A browser in a category ignores its tab and doesn't wait for the title")
    func browser() {
        let overrides: [String: AppCategory] = ["com.google.Chrome": .work]
        let title = "Inbox (3) - levi@birdtown.ai - Gmail"
        #expect(AppCategoryResolver.category(bundleID: "com.google.Chrome", windowTitle: title, overrides: overrides) == .work)
        #expect(AppCategoryResolver.category(bundleID: "com.google.Chrome", windowTitle: nil, overrides: overrides) == .work)
        #expect(!AppCategoryResolver.categoryDependsOnTitle(bundleID: "com.google.Chrome", overrides: overrides))
        // Another browser still follows its tab.
        #expect(AppCategoryResolver.category(bundleID: "com.apple.Safari", windowTitle: title, overrides: overrides) == .email)
        #expect(AppCategoryResolver.categoryDependsOnTitle(bundleID: "com.apple.Safari", overrides: overrides))
    }

    @Test("Moving a browser to Everything else stops tab matching")
    func browserToOther() {
        let overrides: [String: AppCategory] = ["com.google.Chrome": .other]
        let quick = AppContext(
            bundleID: "com.google.Chrome", appName: "Google Chrome",
            category: AppCategoryResolver.category(bundleID: "com.google.Chrome", windowTitle: nil, overrides: overrides))
        let refined = quick.withWindowTitle("general (Channel) - Birdtown - Slack", overrides: overrides)
        #expect(refined.category == .other)
        #expect(refined.windowTitle == "general (Channel) - Birdtown - Slack")
    }

    @Test("The title refines with the same overrides")
    func refinedWithOverrides() {
        let overrides: [String: AppCategory] = ["com.apple.mail": .work]
        let mail = AppContext(bundleID: "com.apple.mail", appName: "Mail", category: .work)
        #expect(mail.withWindowTitle("Inbox", overrides: overrides).category == .work)
    }

    @Test("Built-in categories", arguments: [
        ("com.apple.MobileSMS", AppCategory?.some(.personal)),
        ("com.tinyspeck.slackmacgap", AppCategory?.some(.work)),
        ("com.apple.mail", AppCategory?.some(.email)),
        ("com.apple.Notes", AppCategory?.some(.other)),
        ("com.google.Chrome", AppCategory?.none),
        ("com.google.Chrome.app.abcdefghijklmnop", AppCategory?.none),
    ])
    func builtIn(bundleID: String, expected: AppCategory?) {
        #expect(AppCategoryResolver.builtInCategory(bundleID: bundleID) == expected)
    }

    @Test("Putting an app back where it was built in forgets the override")
    func normalizes() {
        var overrides = AppCategoryResolver.overrides([:], putting: "com.tinyspeck.slackmacgap", in: .personal)
        #expect(overrides == ["com.tinyspeck.slackmacgap": .personal])
        overrides = AppCategoryResolver.overrides(overrides, putting: "com.tinyspeck.slackmacgap", in: .work)
        #expect(overrides.isEmpty)
        // An unlisted app in Everything else is where it already was.
        #expect(AppCategoryResolver.overrides([:], putting: "com.apple.Notes", in: .other).isEmpty)
        // A browser in Everything else is a real change: it stops following the tab.
        #expect(AppCategoryResolver.overrides([:], putting: "com.google.Chrome", in: .other) == ["com.google.Chrome": .other])
        // nil resets.
        overrides = ["com.apple.Notes": .work, "com.apple.mail": .personal]
        #expect(AppCategoryResolver.overrides(overrides, putting: "com.apple.Notes", in: nil) == ["com.apple.mail": .personal])
    }

    @Test("A category lists its built-in apps that stayed, and the ones added")
    func members() {
        let overrides: [String: AppCategory] = [
            "com.apple.mail": .work,
            "com.apple.Notes": .work,
            "com.tinyspeck.slackmacgap": .other,
        ]
        let work = AppCategoryResolver.members(of: .work, overrides: overrides)
        #expect(!work.builtIn.contains("com.tinyspeck.slackmacgap"))
        #expect(work.builtIn.contains("com.hnc.Discord"))
        #expect(work.added == ["com.apple.Notes", "com.apple.mail"])
        let email = AppCategoryResolver.members(of: .email, overrides: overrides)
        #expect(!email.builtIn.contains("com.apple.mail"))
        let other = AppCategoryResolver.members(of: .other, overrides: overrides)
        #expect(other.builtIn.isEmpty)
        #expect(other.added == ["com.tinyspeck.slackmacgap"])
    }
}
