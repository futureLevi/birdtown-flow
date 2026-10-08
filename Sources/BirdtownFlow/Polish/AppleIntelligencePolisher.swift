import Foundation
import FoundationModels
import MurmurKit

/// AI polish with Apple's on-device language model (macOS 26 Foundation Models).
///
/// Private and free: nothing leaves the Mac. It gets the same `PolishPrompt` as the cloud
/// providers, and `PolishService` guards and bounds it exactly the same way.
struct AppleIntelligencePolisher: PolishClient {
    /// A failure with two phrasings: a short note for History, a full sentence for Settings.
    struct Failure: LocalizedError {
        let note: String
        let detail: String

        var errorDescription: String? { detail }
    }

    /// `nil` when the model can run right now, otherwise a sentence for Settings.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off. Turn it on in System Settings to use it here."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready. Try again in a few minutes."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    /// The same, as a History note.
    static var unavailableNote: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Apple Intelligence failed"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "Apple Intelligence isn't supported on this Mac"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is off"
            case .modelNotReady: return "Apple Intelligence is still getting ready"
            @unknown default: return "Apple Intelligence is unavailable"
            }
        @unknown default:
            return "Apple Intelligence is unavailable"
        }
    }

    func polish(_ request: PolishRequest) async throws -> String {
        if let reason = Self.unavailableReason {
            throw Failure(note: Self.unavailableNote, detail: reason)
        }

        let instructions = PolishPrompt.system(for: request)
        // A session warmed at key-down when it was started with these same instructions;
        // otherwise a fresh one, which loads the model now.
        let session = await AppleIntelligenceSessions.shared.take(instructions: instructions)
            ?? LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(
            // Near-deterministic: this is editing, not writing.
            temperature: 0.2,
            // A cleanup is never much longer than what was said; this bounds a runaway.
            maximumResponseTokens: Self.responseTokenLimit(for: request.text)
        )
        do {
            let response = try await session.respond(to: PolishPrompt.user(for: request), options: options)
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.failure(for: error)
        }
    }

    /// Starts a session for the dictation that's about to happen, so the model is loaded and
    /// the instructions read while the person is talking. The text isn't known yet, and the
    /// instructions don't include it.
    static func prewarm(_ request: PolishRequest) {
        guard unavailableReason == nil else { return }
        let instructions = PolishPrompt.system(for: request)
        Task { await AppleIntelligenceSessions.shared.prewarm(instructions: instructions) }
    }

    /// Roughly four characters per token; twice the input leaves room for punctuation and
    /// paragraphing without letting the model ramble on.
    private static func responseTokenLimit(for text: String) -> Int {
        min(4_000, max(256, text.count / 2))
    }

    /// The cases worth telling apart: the model declining content is expected now and then,
    /// while an unsupported language or an over-long dictation is something the user can act on.
    private static func failure(for error: LanguageModelSession.GenerationError) -> Failure {
        switch error {
        case .guardrailViolation:
            Failure(
                note: "Apple Intelligence declined this text",
                detail: "Apple Intelligence declined to rewrite this text, so it was left as dictated."
            )
        case .unsupportedLanguageOrLocale:
            Failure(
                note: "Language not supported by Apple Intelligence",
                detail: "Apple Intelligence doesn't support this language yet."
            )
        case .exceededContextWindowSize:
            Failure(
                note: "Too long for Apple Intelligence",
                detail: "This dictation is too long for the on-device model. Shorter ones will be polished."
            )
        default:
            Failure(
                note: "Apple Intelligence failed",
                detail: "Apple Intelligence couldn't polish this text: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Sessions

/// Keeps one session warmed and waiting for the next dictation. Each session answers exactly
/// one dictation and is never handed out twice, so nothing said earlier rides along.
actor AppleIntelligenceSessions {
    static let shared = AppleIntelligenceSessions()

    /// A session left waiting longer than this is replaced rather than trusted to still be warm.
    static let maxSpareAge: Duration = .seconds(10 * 60)

    private var spare: (instructions: String, session: LanguageModelSession, startedAt: ContinuousClock.Instant)?

    func prewarm(instructions: String) {
        if let spare, spare.instructions == instructions, ContinuousClock.now - spare.startedAt < Self.maxSpareAge {
            return
        }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        spare = (instructions, session, ContinuousClock.now)
    }

    /// The waiting session, if it was started with exactly these instructions. Either way the
    /// spare is used up: a dictation that didn't match leaves nothing worth keeping.
    func take(instructions: String) -> LanguageModelSession? {
        defer { spare = nil }
        guard let spare, spare.instructions == instructions, ContinuousClock.now - spare.startedAt < Self.maxSpareAge
        else { return nil }
        return spare.session
    }
}
