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

/// Rebuilds its content when the title font changes. Font tokens are read as views are built
/// and don't observe the setting themselves, so each window's root carries one of these.
struct TypeTreatmentRoot<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content.id(Settings.shared.typeTreatment)
    }
}
