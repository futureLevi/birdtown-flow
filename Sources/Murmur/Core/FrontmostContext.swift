import AppKit
import ApplicationServices
import Foundation
import MurmurKit

/// Where the user is dictating, captured at key-down.
///
/// Split in two so the key-down path never waits on another process: the app's identity
/// comes from `NSWorkspace` (in-process, instant), and the window title — which needs an
/// Accessibility round trip to the target app — is read off the main thread with a short
/// messaging timeout, so a hung app can't stall us.
@MainActor
enum FrontmostContext {
    /// Bundle ID and name of the frontmost app, categorized without a window title.
    static func quick() -> (context: AppContext, pid: pid_t?) {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let context = AppContext(
            bundleID: bundleID,
            appName: app?.localizedName,
            windowTitle: nil,
            category: AppCategoryResolver.category(bundleID: bundleID, windowTitle: nil)
        )
        return (context, app?.processIdentifier)
    }

    /// `base` with the focused window's title and the category it implies (Gmail in a browser
    /// is email, not "other"). Best-effort: returns `base` if the title can't be read.
    nonisolated static func refined(_ base: AppContext, pid: pid_t?) -> AppContext {
        guard let pid, let title = focusedWindowTitle(pid: pid), !title.isEmpty else { return base }
        var context = base
        context.windowTitle = title
        context.category = AppCategoryResolver.category(bundleID: base.bundleID, windowTitle: title)
        return context
    }

    nonisolated private static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        // Bounds each call below; the default is several seconds.
        AXUIElementSetMessagingTimeout(app, 0.15)

        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let windowElement = unsafeDowncast(window as AnyObject, to: AXUIElement.self)

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }
}
