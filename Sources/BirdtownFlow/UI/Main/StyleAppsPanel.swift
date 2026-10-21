import AppKit
import MurmurKit
import SwiftUI
import UniformTypeIdentifiers

/// The apps in one category, under its tone on the Style page. The built-in ones that are
/// installed, and the ones the person put here themselves; each can move to another category,
/// and a moved one can go back. Choices are saved in `Settings.appCategories` and win over the
/// built-in lists, and over a browser's tab.
struct StyleAppsPanel: View {
    let category: AppCategory

    @Environment(AppModel.self) private var model

    /// Regular apps open right now, offered first in Add an app.
    @State private var running: [RunningApp] = []
    @State private var isChoosingApp = false

    var body: some View {
        let list = rows
        Card(padding: Layout.Style.panelInset) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Apps")
                            .font(Typography.groupTitle)
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Wraps only when the add link needs the room.
                    .layoutPriority(1)
                    Spacer(minLength: Spacing.m)
                    addMenu
                }
                .padding(.bottom, Layout.Style.appsHeadBottom)

                if list.isEmpty {
                    Text(emptyText)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Layout.Style.appRowVertical)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                RowDivider(leadingInset: Layout.Style.appIcon + Layout.Style.appRowGap)
                            }
                            appRow(row)
                        }
                    }
                }

                Text(note)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.Style.appsNoteTop)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Apps in \(category.title)")
        .onAppear(perform: refreshRunning)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshRunning()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshRunning()
        }
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.applicationBundle]) { result in
            guard case .success(let url) = result, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            put(bundleID, name: AppNames.name(at: url), in: category)
        }
        .fileDialogDefaultDirectory(URL(filePath: "/Applications"))
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let bundleID: String
        /// `nil` when the app isn't installed (any more).
        let name: String?
        /// Put here by the person, rather than by the built-in lists.
        let isAdded: Bool

        var id: String { bundleID }
        var title: String { name ?? bundleID }
    }

    /// Built-in apps that aren't installed are left out: a list of apps you don't have
    /// doesn't help you choose. Ones the person added stay, so they can be taken out again.
    private var rows: [Row] {
        let members = AppCategoryResolver.members(of: category, overrides: model.settings.appCategories)
        let builtIn = members.builtIn.compactMap { id in
            AppNames.name(for: id).map { Row(bundleID: id, name: $0, isAdded: false) }
        }
        let added = members.added.map { Row(bundleID: $0, name: AppNames.name(for: $0), isAdded: true) }
        return (builtIn + added).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func appRow(_ row: Row) -> some View {
        HStack(spacing: Layout.Style.appRowGap) {
            AppIcon(bundleID: row.bundleID, name: row.title, size: Layout.Style.appIcon)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(row.title)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(detail(for: row))
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.m)
            Menu {
                menuItems(for: row)
            } label: {
                Image(systemName: "ellipsis")
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .frame(width: Layout.Main.iconButton, height: Layout.Main.iconButton)
            .help("Move \(row.title)")
            .accessibilityLabel("Move \(row.title)")
        }
        .padding(.vertical, Layout.Style.appRowVertical)
        .contentShape(Rectangle())
        .contextMenu { menuItems(for: row) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.title), \(detail(for: row))")
    }

    @ViewBuilder
    private func menuItems(for row: Row) -> some View {
        ForEach(AppCategory.allCases.filter { $0 != category }) { destination in
            Button("Move to \(destination.title)", systemImage: destination.symbol) {
                put(row.bundleID, name: row.title, in: destination)
            }
        }
        if row.isAdded {
            Divider()
            Button(resetTitle(for: row.bundleID), systemImage: "arrow.uturn.backward") {
                put(row.bundleID, name: row.title, in: nil)
            }
        }
    }

    private func detail(for row: Row) -> String {
        var parts: [String] = []
        if row.isAdded {
            switch AppCategoryResolver.builtInCategory(bundleID: row.bundleID) {
            case nil: parts.append("Added by you, for every tab")
            case .other?: parts.append("Added by you")
            case let builtIn?: parts.append("Moved from \(builtIn.title)")
            }
        } else {
            parts.append("Built in")
        }
        if row.name == nil { parts.append("not installed") }
        return parts.joined(separator: ", ")
    }

    /// Where Reset sends an app: back to its built-in category, out of this one, or (for a
    /// browser) back to following the tab.
    private func resetTitle(for bundleID: String) -> String {
        switch AppCategoryResolver.builtInCategory(bundleID: bundleID) {
        case nil: "Follow the tab again"
        case .other?: "Remove from \(category.title)"
        case let builtIn?: "Move back to \(builtIn.title)"
        }
    }

    // MARK: - Adding

    private struct RunningApp: Identifiable, Equatable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    private var addMenu: some View {
        // A browser that follows the tab can be added anywhere, Everything else included.
        let candidates = running.filter { placement(of: $0.bundleID) != category }
        return Menu {
            if candidates.isEmpty {
                Text("No other apps are open")
            } else {
                Section("Open now") {
                    ForEach(candidates) { app in
                        Button(app.name) { put(app.bundleID, name: app.name, in: category) }
                    }
                }
            }
            Divider()
            Button("Choose from Applications\u{2026}") { isChoosingApp = true }
        } label: {
            Label("Add an app", systemImage: "plus")
                .font(Typography.link)
                .foregroundStyle(Palette.accentInk)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Put another app in \(category.title)")
    }

    private func refreshRunning() {
        let me = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != me else { return nil }
            return RunningApp(bundleID: id, name: app.localizedName ?? id)
        }
        let sorted = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if sorted != running { running = sorted }
    }

    /// The category an app is in, or `nil` for a browser that follows the tab.
    private func placement(of bundleID: String) -> AppCategory? {
        model.settings.appCategories[bundleID] ?? AppCategoryResolver.builtInCategory(bundleID: bundleID)
    }

    private func put(_ bundleID: String, name: String, in destination: AppCategory?) {
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        model.settings.setCategory(destination, forApp: bundleID)
        let announcement = placement(of: bundleID).map { "\(name) moved to \($0.title)" }
            ?? "\(name) follows the tab again"
        AccessibilityNotification.Announcement(announcement).post()
    }

    // MARK: - Copy

    private var subtitle: String {
        let style = model.settings.style(for: category).title
        return category == .other
            ? "Every app that isn\u{2019}t in another category uses \(style)."
            : "Dictating into these apps uses \(style)."
    }

    private var emptyText: String {
        category == .other
            ? "No apps moved here yet."
            : "None of the usual apps for this are installed. Add the ones you use."
    }

    private var note: String {
        category == .other
            ? "Move an app here to take it out of its category. A browser moved here stops following the tab."
            : "In a browser the tab decides: Gmail is Email, Slack is Work messages. Add a browser here to use this style for every tab."
    }
}

/// Installed apps' names by bundle ID, looked up once: `NSWorkspace` touches the disk, and the
/// Style page asks for the same few apps on every redraw. `nil` means not installed.
@MainActor
enum AppNames {
    private static var names: [String: String?] = [:]

    static func name(for bundleID: String) -> String? {
        if let cached = names[bundleID] { return cached }
        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { name(at: $0) }
        names[bundleID] = .some(found)
        return found
    }

    static func name(at url: URL) -> String {
        let shown = FileManager.default.displayName(atPath: url.path)
        return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
    }
}
