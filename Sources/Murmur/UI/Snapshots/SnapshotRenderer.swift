import AppKit
import SwiftUI

/// Renders registered screens to PNG files, in light and dark appearance.
///
/// Run with `Murmur --render-snapshots <dir>`. CI does this on every push and publishes the
/// images, which is how the UI gets reviewed without someone sitting at a Mac. Screens are
/// registered in the `SnapshotCatalog` extensions (one file per area, to keep merges clean).
@MainActor
enum SnapshotRenderer {
    struct Shot {
        let name: String
        let size: CGSize
        let view: AnyView

        init<V: View>(_ name: String, size: CGSize, @ViewBuilder view: () -> V) {
            self.name = name
            self.size = size
            self.view = AnyView(view())
        }
    }

    static func run(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let shots = SnapshotCatalog.main + SnapshotCatalog.hud + SnapshotCatalog.setup
        print("[snapshots] rendering \(shots.count) screens into \(directory.path)")
        for shot in shots {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let url = directory.appendingPathComponent("\(shot.name)-\(suffix).png")
                await render(shot, appearance: appearance, to: url)
            }
        }
        print("[snapshots] done")
    }

    private static func render(_ shot: Shot, appearance: NSAppearance.Name, to url: URL) async {
        let rect = NSRect(origin: .zero, size: shot.size)
        let hosting = NSHostingView(
            rootView: shot.view
                .frame(width: shot.size.width, height: shot.size.height)
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
        )
        hosting.frame = rect

        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        // Opaque, like a real window: a clear backdrop shows through translucent sidebars and
        // leaves dark strips at the edges of full-window shots.
        window.backgroundColor = NSColor(Palette.canvas)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.orderFrontRegardless()

        // Let SwiftUI lay out, load images and settle any appear animations.
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(700))
        hosting.layoutSubtreeIfNeeded()
        hosting.display()

        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("[snapshots] \(shot.name): no bitmap")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            print("[snapshots] wrote \(url.lastPathComponent)")
        } catch {
            print("[snapshots] \(shot.name): \(error.localizedDescription)")
        }
    }
}

/// Screens to render. Each area adds its own in a separate file:
/// `SnapshotCatalog+Main.swift`, `+HUD.swift`, `+Setup.swift`.
@MainActor
enum SnapshotCatalog {}
