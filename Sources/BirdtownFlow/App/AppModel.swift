import AppKit
import Foundation
import MurmurKit
import Observation

/// Sections of the main window's sidebar.
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case history
    case dictionary
    case snippets
    case style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .snippets: "Snippets"
        case .style: "Style"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .style: "textformat"
        }
    }
}

/// The composition root. Owns every long-lived object; views receive it through the
/// environment (`@Environment(AppModel.self)`).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings: Settings
    let history: HistoryStore
    let snippets: SnippetStore
    let dictionary: DictionaryStore
    let models: ModelManager
    let permissions: PermissionsMonitor
    let controller: DictationController

    /// Main-window navigation.
    var section: SidebarSection = .home
    /// History row to reveal when navigating from elsewhere (Home, menu bar).
    var focusedRecordID: UUID?

    init(
        settings: Settings = .shared,
        history: HistoryStore = HistoryStore(directory: AppPaths.history),
        snippets: SnippetStore = SnippetStore(fileURL: AppPaths.snippets),
        dictionary: DictionaryStore = .shared
    ) {
        self.settings = settings
        self.history = history
        self.snippets = snippets
        self.dictionary = dictionary
        let models = ModelManager(settings: settings)
        self.models = models
        self.permissions = PermissionsMonitor()
        self.controller = DictationController(
            settings: settings,
            history: history,
            snippets: snippets,
            dictionary: dictionary,
            models: models
        )
    }

    /// Normal launch: arm the hotkey, load the model, tidy history.
    func start() {
        history.applyRetention(
            textDays: settings.historyRetentionDays > 0 ? settings.historyRetentionDays : nil,
            audioDays: settings.audioRetentionDays >= 0 ? settings.audioRetentionDays : nil
        )
        controller.activate()
        controller.polishSettingsChanged()
        Task { await models.prepare() }
    }

    /// Brings the main window forward on a section.
    func show(_ section: SidebarSection) {
        self.section = section
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
