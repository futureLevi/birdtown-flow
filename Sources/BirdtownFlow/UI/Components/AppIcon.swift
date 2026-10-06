import AppKit
import SwiftUI

/// The icon of the app a dictation went to, looked up by bundle ID. Apps that aren't
/// installed (any more) get a quiet monogram tile instead of a broken image.
struct AppIcon: View {
    let bundleID: String?
    /// Used for the monogram when the app can't be found.
    var name: String?
    var size: CGFloat = Layout.appIcon

    var body: some View {
        Group {
            if let image = AppIconCache.icon(for: bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Palette.sunken)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline)
                    )
                    .overlay {
                        Text(monogram)
                            .font(Typography.monogram(size: size * 0.46))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var monogram: String {
        guard let first = name?.trimmingCharacters(in: .whitespaces).first else { return "·" }
        return String(first).uppercased()
    }
}

/// `NSWorkspace` icon lookups touch the disk; history rows ask for the same few apps over
/// and over, so cache hits and misses for the life of the process.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let icon = icons[bundleID] { return icon }
        if missing.contains(bundleID) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}
