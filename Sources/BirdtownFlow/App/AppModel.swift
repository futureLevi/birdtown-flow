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
    /// Admin: polish setups tried out before they're used everywhere.
    case lab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .snippets: "Snippets"
        case .style: "Style"
        case .lab: "Lab"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .style: "textformat"
        case .lab: "flask"
        }
    }

    /// Everyday sections, then admin tools under their own heading.
    static let everyday: [SidebarSection] = [.home, .history, .dictionary, .snippets, .style]
    static let admin: [SidebarSection] = [.lab]
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
    let lab: PolishLabStore
    /// The Lab page's edits, test text and results.
    let bench: LabBench
    let models: ModelManager
    let permissions: PermissionsMonitor
    let controller: DictationController
    /// History deletes waiting out their undo window. Shared by Home and History, so a
    /// delete survives switching pages and either page's Undo (⌘Z) brings it back.
    let historyDeletion: HistoryDeletion
    /// "Transcribe Again" in flight, and what each attempt left for its row to show.
    /// Snapshots swap in a fresh tracker so their state stays in one shot.
    @ObservationIgnored var retries: RetryTracker = .shared

    /// Main-window navigation. To move around from outside the window, call `show(_:)`,
    /// `showHistory(revealing:)` or `showSettings(_:)` rather than setting these.
    var section: SidebarSection = .home
    /// History row to reveal: History scrolls to it, selects it and flashes it, then clears
    /// this. Set it through `showHistory(revealing:)`.
    var focusedRecordID: UUID?
    /// The Settings section showing in the main window's Settings modal, or `nil` when it's
    /// closed. Open it through `showSettings(_:)`; the modal switches sections by setting it.
    var settingsTab: SettingsTab?
    /// The main window's sidebar tucked away (its Hide sidebar button, or ⌃⌘S).
    var sidebarHidden = false

    init(
        settings: Settings = .shared,
        history: HistoryStore = HistoryStore(directory: AppPaths.history),
        snippets: SnippetStore = SnippetStore(fileURL: AppPaths.snippets),
        dictionary: DictionaryStore = .shared,
        lab: PolishLabStore = PolishLabStore(fileURL: AppPaths.lab)
    ) {
        self.settings = settings
        self.history = history
        self.snippets = snippets
        self.dictionary = dictionary
        self.lab = lab
        self.bench = LabBench(settings: settings, lab: lab, dictionary: dictionary, snippets: snippets)
        let models = ModelManager(settings: settings, boostVocabulary: { dictionary.biasPhrases })
        self.models = models
        self.permissions = PermissionsMonitor()
        self.historyDeletion = HistoryDeletion(store: history, undoWindow: Motion.undoWindow)
        self.controller = DictationController(
            settings: settings,
            history: history,
            snippets: snippets,
            dictionary: dictionary,
            lab: lab,
            models: models
        )
    }

    /// Normal launch: arm the hotkey, load the model, tidy history (and keep it tidy).
    func start() {
        applyRetention()
        keepApplyingRetention()
        controller.activate()
        controller.polishSettingsChanged()
        Task { await models.prepare() }
        // A delete still inside its undo window is meant: finish it before quitting, or the
        // dictation would come back on the next launch.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so this is provably the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.historyDeletion.commit()
                // Dictionary and snippet deletes have the same undo window; both save at once.
                self.dictionary.commitDeletion()
                self.snippets.commitDeletion()
                self.history.flush()
            }
        }
    }

    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    // MARK: - Retention
    //
    // Birdtown Flow is an open-at-login menu bar app that can run for weeks, so applying the
    // History limits only at launch would keep month-old text under a "7 days" setting.

    /// Applies the History retention settings now. Records a "Transcribe Again" is still
    /// working on are left for the next sweep.
    func applyRetention() {
        history.applyRetention(
            HistoryRetention(
                settingsHistoryDays: settings.historyRetentionDays,
                settingsAudioDays: settings.audioRetentionDays
            ),
            sparing: retries.inFlight
        )
    }

    /// Re-applies retention hourly, after the Mac wakes (a timer doesn't fire during sleep),
    /// and as soon as either retention setting changes.
    private func keepApplyingRetention() {
        guard retentionTimer == nil else { return }
        let timer = Timer(timeInterval: HistoryRetention.sweepInterval, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop below, so this is provably the main thread.
            MainActor.assumeIsolated {
                self?.applyRetention()
            }
        }
        // Nobody waits on it: let the system batch it with other wake-ups.
        timer.tolerance = HistoryRetention.sweepInterval / 10
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so this is provably the main thread.
            MainActor.assumeIsolated {
                self?.applyRetention()
            }
        }
        observeRetentionSettings()
    }

    private func observeRetentionSettings() {
        withObservationTracking {
            _ = settings.historyRetentionDays
            _ = settings.audioRetentionDays
        } onChange: { [weak self] in
            // Fires before the new value is stored; hop so the sweep reads the new one.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeRetentionSettings()
                self.applyRetention()
            }
        }
    }

    @ObservationIgnored private var retentionTimer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    // MARK: - Navigation
    //
    // The one way to move the main window from anywhere (the HUD, the menu bar, Settings,
    // other pages). Each brings the window forward, reopening it if it was closed.

    /// Brings the main window forward on a section, closing Settings if it was open.
    func show(_ section: SidebarSection) {
        self.section = section
        settingsTab = nil
        bringMainWindowForward()
    }

    /// Brings the main window forward on History, scrolled to `id`, selected and flashed.
    /// With `nil`, or an id that's no longer in History, it just opens History.
    func showHistory(revealing id: UUID? = nil) {
        if let id, history.record(id: id) != nil, !historyDeletion.isPending(id) {
            focusedRecordID = id
        }
        show(.history)
    }

    /// Brings the main window forward with Settings open over it, on `tab`. Settings is a
    /// modal inside the main window, not a window of its own. Without a tab it opens where it
    /// already is (⌘, while it's open keeps the section), or on General.
    func showSettings(_ tab: SettingsTab? = nil) {
        settingsTab = tab ?? settingsTab ?? .general
        bringMainWindowForward()
    }

    /// Closes the Settings modal, leaving the main window where it was.
    func closeSettings() {
        settingsTab = nil
    }

    private func bringMainWindowForward() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Closed: SwiftUI only reopens a `Window` scene through `openWindow`, which needs a
        // view. File › Open Birdtown Flow (⌘O, in `MurmurCommands`) is that call, so use it.
        guard let menu = NSApp.mainMenu else { return }
        for item in menu.items {
            guard let submenu = item.submenu,
                  let index = submenu.items.firstIndex(where: {
                      $0.keyEquivalent == "o" && $0.keyEquivalentModifierMask == .command && $0.isEnabled
                  })
            else { continue }
            submenu.performActionForItem(at: index)
            return
        }
    }
}
