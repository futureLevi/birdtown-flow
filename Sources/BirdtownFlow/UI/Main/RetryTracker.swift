import Foundation
import MurmurKit
import Observation

/// Which history records are being re-transcribed right now, and what each attempt left
/// behind for the row to show.
///
/// Lives outside the rows on purpose: History is a lazy list, so a row that scrolls away is
/// destroyed and its `@State` with it. If "retrying" lived in the row, scrolling back would
/// show an enabled Retry button mid-retry, and a second click would start a second
/// transcription of the same audio racing the first.
///
/// Transcribing a dictation that already worked again never costs its text: an error or
/// silence puts the old record back (see `Retranscription`), and new text keeps the old
/// for "Restore Earlier Text" until the app quits.
@MainActor
@Observable
final class RetryTracker {
    static let shared = RetryTracker()

    private(set) var inFlight: Set<UUID> = []
    /// The text a "Transcribe Again" replaced, by record: the earliest, so restoring after
    /// several attempts goes back to what was first typed. Session only.
    private(set) var replaced: [UUID: HistoryRecord] = [:]
    /// Why the last attempt on a dictation that already had text was set aside.
    private(set) var keptReasons: [UUID: String] = [:]

    func isRetrying(_ id: UUID) -> Bool { inFlight.contains(id) }

    /// Transcribes `record`'s audio again unless that's already happening. Returns once the
    /// outcome is settled in history (`nil` if it was already in flight or got deleted).
    @discardableResult
    func retry(
        _ record: HistoryRecord,
        controller: DictationController,
        history: HistoryStore
    ) async -> Retranscription.Resolution? {
        let id = record.id
        guard !inFlight.contains(id) else { return nil }
        let previous = history.record(id: id) ?? record
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        keptReasons[id] = nil

        await controller.retry(previous)

        guard let result = history.record(id: id) else { return nil }
        let resolution = Retranscription.resolve(previous: previous, result: result)
        switch resolution {
        case .updated:
            break
        case .replaced(let earlier):
            if replaced[id] == nil { replaced[id] = earlier }
        case .keptPrevious(let earlier, let reason):
            history.update(earlier)
            keptReasons[id] = Self.sentence(reason)
        }
        return resolution
    }

    /// Puts back the text a "Transcribe Again" replaced.
    func restore(_ id: UUID, in history: HistoryStore) {
        guard let earlier = replaced.removeValue(forKey: id), history.record(id: id) != nil else { return }
        history.update(earlier)
        keptReasons[id] = nil
    }

    func dismissReason(_ id: UUID) {
        keptReasons[id] = nil
    }

    /// Snapshots only: show rows mid-retry, kept or replaced without transcribing anything.
    func preview(
        inFlight: Set<UUID> = [],
        replaced: [UUID: HistoryRecord] = [:],
        keptReasons: [UUID: String] = [:]
    ) {
        self.inFlight = inFlight
        self.replaced = replaced
        self.keptReasons = keptReasons
    }

    /// Engine messages don't always end in a full stop; the row puts another sentence after.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }
}
