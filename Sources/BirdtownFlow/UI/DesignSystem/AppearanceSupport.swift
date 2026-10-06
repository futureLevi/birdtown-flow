import AppKit
import SwiftUI

extension AppearancePreference {
    /// Sets the whole app's appearance. Every window follows `NSApp.appearance` unless it sets
    /// its own, and the adaptive colour tokens resolve against it at draw time.
    @MainActor
    func apply() {
        let appearance: NSAppearance? = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        NSApp?.appearance = appearance
    }
}
