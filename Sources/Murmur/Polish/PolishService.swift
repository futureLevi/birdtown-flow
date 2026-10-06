import Foundation
import MurmurKit

// CONTRACT — owned by the speech agent. Placeholder bodies until the real one lands.

/// Routes a transcript to the configured AI polisher, with a hard timeout and `PolishGuard`.
/// Never throws: any failure returns the input unchanged with a note for History.
@MainActor
final class PolishService {
    struct Outcome: Sendable {
        var text: String
        /// The provider whose output was used; `nil` when polish was off, failed or rejected.
        var provider: PolishProvider?
        /// Why polish wasn't used, for History ("timed out", "no API key"…). `nil` on success or when off.
        var note: String?
    }

    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    func polish(_ request: PolishRequest) async -> Outcome {
        Outcome(text: request.text, provider: nil, note: nil)
    }

    /// For the Settings "Test" button: polishes a fixed sentence with the current provider.
    func test() async -> Result<String, Error> {
        .failure(PolishError.emptyResponse)
    }

    /// Whether the selected provider can run right now (key present, Apple Intelligence on…),
    /// and if not, a short reason for the UI.
    func availability() -> (available: Bool, reason: String?) {
        (settings.polishProvider == .off, nil)
    }
}
