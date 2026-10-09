import Foundation

/// What to keep after transcribing a History record's audio again.
///
/// Retrying a failed dictation should take whatever the new attempt gives. Transcribing a
/// dictation that already worked is different: a worse result is the user's call (they can
/// restore the old text), but an error or silence must never cost them text they already had.
public enum Retranscription {
    public enum Resolution: Equatable, Sendable {
        /// The record had no good text before; the new attempt stands, whatever it was.
        case updated
        /// The new text replaced good text. `previous` is what to restore on request.
        case replaced(previous: HistoryRecord)
        /// The new attempt failed or heard nothing; put `previous` back and say why.
        case keptPrevious(previous: HistoryRecord, reason: String)
    }

    /// Whether `record` holds text the user already got (typed or on the clipboard).
    public static func hasGoodText(_ record: HistoryRecord) -> Bool {
        (record.outcome == .inserted || record.outcome == .copied) && record.hasText
    }

    public static func resolve(previous: HistoryRecord, result: HistoryRecord) -> Resolution {
        guard hasGoodText(previous) else { return .updated }
        switch result.outcome {
        case .inserted, .copied:
            return result.hasText
                ? .replaced(previous: previous)
                : .keptPrevious(previous: previous, reason: "No speech was heard this time.")
        case .failed:
            let message = result.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .keptPrevious(previous: previous, reason: message.isEmpty ? "Something went wrong." : message)
        case .cancelled:
            return .keptPrevious(previous: previous, reason: "It was cancelled.")
        case .empty:
            return .keptPrevious(previous: previous, reason: "No speech was heard this time.")
        }
    }
}
