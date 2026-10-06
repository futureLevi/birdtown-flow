import Foundation
import Security

/// API keys live in the login keychain, never in UserDefaults.
///
/// Generic-password items under the service `io.github.futurelevi.murmur`, one account per
/// provider. The file-based login keychain rather than the data-protection keychain on
/// purpose: the latter needs a keychain-access-group entitlement that ad-hoc signed builds
/// don't have, and would fail with `errSecMissingEntitlement`.
///
/// Keys are never logged; failures log only the OSStatus.
enum Keychain {
    enum Account: String {
        case anthropic = "anthropic-api-key"
        case openAICompatible = "openai-compatible-api-key"

        /// What Keychain Access shows for the item.
        fileprivate var label: String {
            switch self {
            case .anthropic: "Murmur: Anthropic API key"
            case .openAICompatible: "Murmur: OpenAI-compatible API key"
            }
        }
    }

    static let service = "io.github.futurelevi.murmur"

    /// The stored key, or `nil` when none is set.
    static func string(for account: Account) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Log.polish.error("keychain read failed (\(status, privacy: .public)) for \(account.rawValue, privacy: .public)")
            }
            return nil
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether a key is stored, for UI that only needs to show "set" or "not set".
    static func hasValue(for account: Account) -> Bool {
        string(for: account) != nil
    }

    /// `nil` or empty removes the item. Surrounding whitespace is trimmed, because keys pasted
    /// from a web page or a terminal often carry a trailing newline the API would reject.
    static func set(_ value: String?, for account: Account) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query = baseQuery(for: account)

        guard !trimmed.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound {
                Log.polish.error("keychain delete failed (\(status, privacy: .public)) for \(account.rawValue, privacy: .public)")
            }
            return
        }

        let data = Data(trimmed.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = account.label
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Log.polish.error("keychain write failed (\(status, privacy: .public)) for \(account.rawValue, privacy: .public)")
        }
    }

    private static func baseQuery(for account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }
}
