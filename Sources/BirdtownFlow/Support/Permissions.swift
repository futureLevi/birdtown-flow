import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// The two privacy grants the app can't work without, and the ways to ask for them.
///
/// The microphone records you, and Accessibility does everything else: the hotkey's event
/// tap and typing into other apps both depend on it. The microphone can be requested in
/// code. Accessibility can't: the most we can do is have macOS show its alert, after which
/// the user turns the switch on in System Settings themselves. The grant is tied to the
/// app's code signature, so a build signed differently is a stranger to TCC.
@MainActor
enum Permissions {
    /// A pane of System Settings › Privacy & Security, by its URL anchor.
    private enum PrivacyPane: String {
        case accessibility = "Privacy_Accessibility"
        case microphone = "Privacy_Microphone"
    }

    private static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var hasMicrophone: Bool { microphoneStatus == .authorized }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Asks once, the first time; after that the answer stands until the user changes it in
    /// System Settings, so a denial just reports `false`.
    static func requestMicrophone() async -> Bool {
        let status = microphoneStatus
        guard status == .notDetermined else { return status == .authorized }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Has macOS show its "would like to control this computer" alert when the app isn't
    /// trusted yet. Returns whether it already is.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        // The option's name as a plain string: the SDK's `kAXTrustedCheckOptionPrompt` is a
        // mutable global, which strict concurrency won't let us read.
        let showAlert = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(showAlert)
    }

    static func openAccessibilitySettings() {
        openPane(.accessibility)
    }

    static func openMicrophoneSettings() {
        openPane(.microphone)
    }

    private static func openPane(_ pane: PrivacyPane) {
        let address = "x-apple.systempreferences:com.apple.preference.security?" + pane.rawValue
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
