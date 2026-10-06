import AppKit
import SwiftUI

// PLACEHOLDER — owned by the hud agent.

/// Owns the floating, non-activating HUD panel and keeps it in sync with the controller.
@MainActor
final class HUDController {
    static let shared = HUDController()

    func attach(to model: AppModel) {}
}
