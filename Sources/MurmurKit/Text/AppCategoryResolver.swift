import Foundation

/// Maps the frontmost app to an `AppCategory`.
///
/// Native apps are recognised by bundle ID. Browsers (and web apps installed from them) host
/// Gmail, Slack and WhatsApp alike, so for those the front window's title decides.
public enum AppCategoryResolver {
    public static let personalApps: Set<String> = [
        "com.apple.MobileSMS",  // Messages
        "com.apple.iChat",  // Messages, older macOS
        "net.whatsapp.WhatsApp",
        "desktop.WhatsApp",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "org.whispersystems.signal-desktop",
        "com.facebook.archon",  // Messenger
        "jp.naver.line.mac",
        "com.viber.osx",
        "com.tencent.xinWeChat",
    ]

    public static let workApps: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.hnc.Discord",
        "com.hnc.DiscordPTB",
        "com.hnc.DiscordCanary",
        "com.linear",
        "us.zoom.xos",
        "Mattermost.Desktop",
        "com.basecamp.bc3-mac",
        "Cisco-Systems.Spark",  // Webex
        "chat.rocket",
        "org.zulip.zulip-electron",
    ]

    public static let emailApps: Set<String> = [
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.superhuman.electron",
        "com.readdle.smartemail-Mac",  // Spark
        "com.readdle.SparkDesktop",  // Spark 3
        "com.mimestream.Mimestream",
        "it.bloop.airmail2",
        "io.canarymail.mac",
        "com.postbox-inc.postbox",
        "org.mozilla.thunderbird",
        "com.freron.MailMate",
        "com.edisonmail.edisonmail",
        "ch.protonmail.desktop",
    ]

    public static let browsers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",  // Arc
        "company.thebrowser.dia",  // Dia
        "ai.perplexity.comet",  // Comet
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "app.zen-browser.zen",
        "org.chromium.Chromium",
        "com.kagi.kagimacOS",  // Orion
    ]

    /// Web apps installed to the Dock or as PWAs get generated bundle IDs under these prefixes.
    static let webAppPrefixes = ["com.apple.Safari.WebApp", "com.google.Chrome.app.", "com.microsoft.edgemac.app."]

    /// Title keywords, checked as whole words. Order matters only within one title segment.
    static let titleKeywords: [(category: AppCategory, words: [String])] = [
        (.email, ["Gmail", "Inbox", "Outlook", "Fastmail", "Proton Mail", "Yahoo Mail", "iCloud Mail", "Superhuman"]),
        (.work, ["Slack", "Microsoft Teams", "Teams", "Discord", "Linear", "Google Chat", "Mattermost", "Basecamp"]),
        (.personal, ["WhatsApp", "Messenger", "Messages", "Telegram"]),
    ]

    /// Ordinary words that only name the app when they are the whole segment ("Linear", not
    /// "Linear algebra - Wikipedia").
    static let wholeSegmentKeywords: Set<String> = ["Linear", "Teams"]

    public static func category(bundleID: String?, windowTitle: String?) -> AppCategory {
        guard let bundleID, !bundleID.isEmpty else { return .other }
        if personalApps.contains(bundleID) { return .personal }
        if workApps.contains(bundleID) { return .work }
        if emailApps.contains(bundleID) { return .email }
        if isBrowser(bundleID), let windowTitle {
            return category(forWindowTitle: windowTitle) ?? .other
        }
        return .other
    }

    public static func isBrowser(_ bundleID: String) -> Bool {
        browsers.contains(bundleID) || webAppPrefixes.contains { bundleID.hasPrefix($0) }
    }

    /// Whether the front window's title can change `bundleID`'s category: a browser, or a web
    /// app installed from one. Every other app is categorized by its bundle ID alone, so a
    /// context read without the title (key-down does, to stay instant) already has the
    /// category the dictation will use.
    public static func categoryDependsOnTitle(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        if personalApps.contains(bundleID) || workApps.contains(bundleID) || emailApps.contains(bundleID) {
            return false
        }
        return isBrowser(bundleID)
    }

    /// Web apps name themselves in a title segment — usually the last ("Inbox (3) - me@x.com -
    /// Gmail"), sometimes the first ("Messenger | Facebook"). Segments are checked last, first,
    /// then the rest, so a Gmail subject line that mentions Slack still reads as email.
    static func category(forWindowTitle title: String) -> AppCategory? {
        let segments = title
            .components(separatedBy: CharacterSet(charactersIn: "-|—–·•"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return nil }
        var ordered = [segments[segments.count - 1]]
        if segments.count > 1 { ordered.append(segments[0]) }
        if segments.count > 2 { ordered += segments[1..<(segments.count - 1)] }
        for segment in ordered {
            for (category, words) in titleKeywords where words.contains(where: { contains(segment, word: $0) }) {
                return category
            }
        }
        return nil
    }

    private static let unreadCount = makeRegex("^\\(\\d+\\)\\s*|\\s*\\(\\d+\\)$")

    private static func contains(_ text: String, word: String) -> Bool {
        if wholeSegmentKeywords.contains(word) {
            return unreadCount.replacingMatches(in: text, template: "").caseInsensitiveCompare(word) == .orderedSame
        }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
        // "Messages" is an ordinary word too; only the capitalised app name counts.
        let caseSensitive = word == "Messages"
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
        else { return false }
        return regex.matches(text)
    }
}

extension AppContext {
    /// This context with the focused window's title, and the category the title implies (Gmail
    /// in a browser is email, not "other"). A title that couldn't be read, or an empty one,
    /// changes nothing.
    public func withWindowTitle(_ title: String?) -> AppContext {
        guard let title, !title.isEmpty else { return self }
        var context = self
        context.windowTitle = title
        context.category = AppCategoryResolver.category(bundleID: bundleID, windowTitle: title)
        return context
    }
}
