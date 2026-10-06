import Foundation
import ServiceManagement

/// Registers Birdtown Flow as a login item through `SMAppService`.
///
/// The system owns this state — people can also flip it in System Settings → General →
/// Login Items — so it is always read back from `SMAppService` rather than mirrored in
/// `Settings`, where it could drift out of date.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registered, but waiting for the user to approve it in System Settings.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// - Throws: the `SMAppService` error, e.g. when the app isn't running from an app bundle.
    static func setEnabled(_ enabled: Bool) throws {
        let status = SMAppService.mainApp.status
        if enabled {
            guard status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard status == .enabled || status == .requiresApproval else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
