import MurmurKit
import SwiftUI

/// The speech model's state, flattened for display.
enum ModelDisplayState: Equatable, Sendable {
    case notDownloaded
    case downloading(Double?)
    case loading
    case ready
    case failed(String)

    init(_ state: ModelManager.State) {
        switch state {
        case .notDownloaded: self = .notDownloaded
        case .downloading(let progress): self = .downloading(progress)
        case .loading: self = .loading
        case .ready: self = .ready
        case .failed(let message): self = .failed(message)
        }
    }
}

/// Everything the sidebar footer and Home banners say about the system, gathered in one
/// value so snapshots can show a healthy (or broken) Mac without touching real state.
struct SystemStatus: Equatable, Sendable {
    var accessibility: Bool
    var microphone: Bool
    var hotkeyActive: Bool
    var model: ModelDisplayState
    /// Forces the footer's recording line, for snapshots. `live` leaves it off: the footer
    /// reads the controller's phase itself, so the main window doesn't observe every phase
    /// change (and Home doesn't re-render) during a dictation.
    var isRecording: Bool
    var engineName: String
    var engineDownloadSize: String
    var pushToTalkKey: String

    @MainActor
    static func live(_ model: AppModel) -> SystemStatus {
        SystemStatus(
            accessibility: model.permissions.accessibility,
            microphone: model.permissions.microphone,
            hotkeyActive: model.controller.isHotkeyActive,
            model: ModelDisplayState(model.models.state),
            isRecording: false,
            engineName: model.settings.engine.displayName,
            engineDownloadSize: model.settings.engine.downloadSize,
            pushToTalkKey: model.settings.pushToTalkKey.displayName
        )
    }
}

/// Overrides used only by snapshots: fixed status, name and starting state, so rendered
/// screens are deterministic and don't depend on the CI machine.
struct MainPreview: Sendable {
    var status: SystemStatus?
    var firstName: String?
    var historyQuery = ""
    var originalRecordID: UUID?
    /// Seconds into the live orb's turn, so recording states render the same frame every time.
    var orbPhase: Double?
}

extension EnvironmentValues {
    @Entry var mainPreview = MainPreview()
}

extension View {
    /// Centres page content at the reading measure with page padding.
    func pageLayout() -> some View {
        self
            .frame(maxWidth: Layout.contentMaxWidth, alignment: .leading)
            .padding(Spacing.page)
            .frame(maxWidth: .infinity)
    }
}
