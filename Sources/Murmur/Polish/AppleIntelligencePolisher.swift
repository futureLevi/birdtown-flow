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

        let session = LanguageModelSession(instructions: PolishPrompt.system(for: request))
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
