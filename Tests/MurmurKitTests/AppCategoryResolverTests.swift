import Testing
@testable import MurmurKit

@Suite("AppCategoryResolver")
struct AppCategoryResolverTests {
    @Test("Native apps by bundle ID", arguments: [
        ("com.apple.MobileSMS", AppCategory.personal),
        ("net.whatsapp.WhatsApp", .personal),
        ("desktop.WhatsApp", .personal),
        ("ru.keepcoder.Telegram", .personal),
        ("org.telegram.desktop", .personal),
        ("org.whispersystems.signal-desktop", .personal),
        ("com.facebook.archon", .personal),
        ("com.tinyspeck.slackmacgap", .work),
        ("com.microsoft.teams2", .work),
        ("com.hnc.Discord", .work),
        ("com.linear", .work),
        ("us.zoom.xos", .work),
        ("com.apple.mail", .email),
        ("com.microsoft.Outlook", .email),
        ("com.superhuman.electron", .email),
        ("com.readdle.smartemail-Mac", .email),
        ("com.mimestream.Mimestream", .email),
        ("it.bloop.airmail2", .email),
        ("io.canarymail.mac", .email),
        ("com.apple.TextEdit", .other),
        ("com.microsoft.VSCode", .other),
    ])
    func nativeApps(bundleID: String, expected: AppCategory) {
        // A misleading title must not override a known native app.
        #expect(AppCategoryResolver.category(bundleID: bundleID, windowTitle: "Gmail") == expected)
    }

    @Test("Browsers use the window title", arguments: [
        ("com.google.Chrome", "Inbox (12) - levi@birdtown.ai - Gmail", AppCategory.email),
        ("com.apple.Safari", "Mail - Levi Matkins - Outlook", .email),
        ("company.thebrowser.Browser", "general (Channel) - Birdtown - Slack", .work),
        ("com.microsoft.edgemac", "Chat | Microsoft Teams", .work),
        ("org.mozilla.firefox", "#launch | Birdtown - Discord", .work),
        ("com.brave.Browser", "(3) WhatsApp", .personal),
        ("company.thebrowser.dia", "Messenger | Facebook", .personal),
        ("ai.perplexity.comet", "Messages for web", .personal),
        ("com.google.Chrome", "Re: Slack invite - levi@birdtown.ai - Gmail", .email),
        ("com.google.Chrome", "Linear algebra - Wikipedia", .other),
        ("com.google.Chrome", "Signal processing - Wikipedia", .other),
        ("com.apple.Safari", "The messages we send - Medium", .other),
        ("com.google.Chrome.app.abcdefghijklmnop", "Slack", .work),
        ("com.apple.Safari", "", .other),
    ])
    func browsers(bundleID: String, title: String, expected: AppCategory) {
        #expect(AppCategoryResolver.category(bundleID: bundleID, windowTitle: title) == expected)
    }

    @Test("Unknown or missing context is 'other'")
    func missing() {
        #expect(AppCategoryResolver.category(bundleID: nil, windowTitle: "Gmail") == .other)
        #expect(AppCategoryResolver.category(bundleID: "", windowTitle: nil) == .other)
        #expect(AppCategoryResolver.category(bundleID: "com.google.Chrome", windowTitle: nil) == .other)
        #expect(AppCategoryResolver.category(bundleID: "com.apple.Notes", windowTitle: "Gmail") == .other)
    }
}
