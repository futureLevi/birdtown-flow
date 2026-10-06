import Foundation
import MurmurKit
import Observation

/// Which history records are being re-transcribed right now.
///
/// Lives outside the rows on purpose: History is a lazy list, so a row that scrolls away is
/// destroyed and its `@State` with it. If "retrying" lived in the row, scrolling back would
/// show an enabled Retry button mid-retry, and a second click would start a second
/// transcription of the same audio racing the first.
@MainActor
@Observable
final class RetryTracker {
    static let shared = RetryTracker()

    private(set) var inFlight: Set<UUID> = []

    func isRetrying(_ id: UUID) -> Bool { inFlight.contains(id) }

    /// Retries `record` unless it's already being retried. Returns once the controller has
    /// written the outcome back to history.
    func retry(_ record: HistoryRecord, using controller: DictationController) async {
        guard !inFlight.contains(record.id) else { return }
        inFlight.insert(record.id)
        defer { inFlight.remove(record.id) }
        await controller.retry(record)
    }
}
