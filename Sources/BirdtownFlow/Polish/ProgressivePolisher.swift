import Foundation
import MurmurKit

/// Polishes the finished parts of a long dictation while the person is still talking, so
/// key-up only waits for the last part. One per dictation session.
///
/// Not built yet: it polishes nothing, and `PolishService.polishLong` polishes everything at
/// key-up as before.
@MainActor
final class ProgressivePolisher {
    private let service: PolishService
    private let settings: Settings
    private var template: PolishRequest?
    private var configuration: PolishConfiguration?
    private var options = PipelineOptions()

    init(service: PolishService, settings: Settings) {
        self.service = service
        self.settings = settings
    }

    /// Called once the frontmost context is known; `template.text` is "".
    func configure(template: PolishRequest, configuration: PolishConfiguration?, options: PipelineOptions) {
        self.template = template
        self.configuration = configuration
        self.options = options
    }

    /// The raw text of the windows transcribed so far (`LiveDictation.onCommittedText`).
    func committedTextDidChange(_ raw: String) {}

    /// Esc, a discarded recording, or processing is over: stops polishing and forgets results.
    func cancel() {}
}

/// How a dictation's text was polished, for the timing summary (`Log.timing`).
struct PolishReport: Sendable {
    var line = TimingLine("polish")
}
