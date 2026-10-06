import Foundation
import Security

// CONTRACT — owned by the speech agent.

/// API keys live in the login keychain, never in UserDefaults.
enum Keychain {
    enum Account: String {
        case anthropic = "anthropic-api-key"
        case openAICompatible = "openai-compatible-api-key"
    }

    static func string(for account: Account) -> String? { nil }

    /// `nil` or empty removes the item.
    static func set(_ value: String?, for account: Account) {}
}
