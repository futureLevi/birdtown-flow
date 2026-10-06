import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// CONTRACT — owned by the MurmurKit agent.
//
// The app's PolishService picks a provider, calls `polish`, and runs the result through
// `PolishGuard.accept` before trusting it. Any error, timeout or rejection falls back to the
// deterministic text — polish can make dictation better, never worse.

public protocol PolishClient: Sendable {
    func polish(_ request: PolishRequest) async throws -> String
}

public enum PolishError: LocalizedError, Sendable {
    case missingAPIKey
    case http(status: Int, message: String)
    case emptyResponse
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No API key is set."
        case .http(let status, let message): "The server returned \(status): \(message)"
        case .emptyResponse: "The model returned nothing."
        case .timedOut: "Polish took too long, so the unpolished text was used."
        }
    }
}

/// The instructions every provider gets.
public enum PolishPrompt {
    public static func system(for request: PolishRequest) -> String {
        "Clean up this dictated text. Return only the text."
    }

    public static func user(for request: PolishRequest) -> String {
        request.text
    }
}

/// Decides whether a model's rewrite can be trusted over the original.
public enum PolishGuard {
    /// Returns the cleaned output, or `nil` if it looks like the model answered, refused,
    /// added commentary or invented content instead of editing.
    public static func accept(_ output: String, original: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Anthropic Messages API.
public struct AnthropicClient: PolishClient {
    public static let defaultModel = "claude-haiku-4-5"

    public var apiKey: String
    public var model: String

    public init(apiKey: String, model: String = AnthropicClient.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    public func polish(_ request: PolishRequest) async throws -> String {
        throw PolishError.emptyResponse
    }
}

/// Any OpenAI-compatible `/chat/completions` endpoint.
public struct OpenAICompatibleClient: PolishClient {
    public var baseURL: URL
    public var apiKey: String
    public var model: String

    public init(baseURL: URL, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    public func polish(_ request: PolishRequest) async throws -> String {
        throw PolishError.emptyResponse
    }
}
