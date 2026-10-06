import Foundation
import MurmurKit

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

    /// What the Settings "Test" button sends: fillers, a stutter, a spoken number and a name,
    /// so a working provider visibly earns its keep.
    static let testSentence =
        "um so i think we should uh move the the meeting to thursday at like three pm and send the deck to sarah before then"

    /// The test allows for a cold connection; dictation itself uses `settings.polishTimeout`.
    private static let testTimeLimit: Double = 15

    init(settings: Settings) {
        self.settings = settings
    }

    func polish(_ request: PolishRequest) async -> Outcome {
        let provider = settings.polishProvider
        let unchanged = Outcome(text: request.text, provider: nil, note: nil)
        guard provider != .off,
              !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return unchanged }

        let client: any PolishClient
        switch makeClient(for: provider) {
        case .success(let made):
            client = made
        case .failure(let unavailable):
            Log.polish.info("polish skipped: \(unavailable.note, privacy: .public)")
            return Outcome(text: request.text, provider: nil, note: unavailable.note)
        }

        let limit = timeLimit
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let output = try await HardDeadline.run(within: .seconds(limit)) {
                try await client.polish(request)
            }
            let elapsed = Self.seconds(clock.now - started)
            guard let accepted = PolishGuard.accept(output, original: request.text) else {
                Log.polish.info("\(provider.rawValue, privacy: .public) rewrite rejected by the guard")
                return Outcome(text: request.text, provider: nil, note: "Rewrite rejected: it changed what was said")
            }
            Log.polish.info("\(provider.rawValue, privacy: .public) polished in \(elapsed, format: .fixed(precision: 2))s")
            return Outcome(text: accepted, provider: provider, note: nil)
        } catch {
            let note = Self.note(for: error, limit: limit)
            Log.polish.info("polish fell back (\(provider.rawValue, privacy: .public)): \(note, privacy: .public)")
            return Outcome(text: request.text, provider: nil, note: note)
        }
    }

    /// For the Settings "Test" button: polishes a fixed sentence with the current provider.
    func test() async -> Result<String, Error> {
        let provider = settings.polishProvider
        guard provider != .off else { return .failure(TestFailure(message: "AI polish is off.")) }

        let client: any PolishClient
        switch makeClient(for: provider) {
        case .success(let made):
            client = made
        case .failure(let unavailable):
            return .failure(TestFailure(message: unavailable.reason))
        }

        let request = PolishRequest(
            text: Self.testSentence,
            style: settings.style(for: .email),
            category: .email,
            appName: "Mail",
            vocabulary: []
        )
        let limit = max(timeLimit, Self.testTimeLimit)
        do {
            let output = try await HardDeadline.run(within: .seconds(limit)) {
                try await client.polish(request)
            }
            guard let accepted = PolishGuard.accept(output, original: request.text) else {
                return .failure(TestFailure(
                    message: "The model replied, but rewrote too freely, so dictation would keep the original text. It said: “\(output.trimmingCharacters(in: .whitespacesAndNewlines))”"
                ))
            }
            return .success(accepted)
        } catch {
            return .failure(TestFailure(message: Self.explanation(for: error, limit: limit)))
        }
    }

    /// Whether the selected provider can run right now (key present, Apple Intelligence on…),
    /// and if not, a short reason for the UI.
    func availability() -> (available: Bool, reason: String?) {
        let provider = settings.polishProvider
        guard provider != .off else { return (true, nil) }
        switch makeClient(for: provider) {
        case .success:
            return (true, nil)
        case .failure(let unavailable):
            return (false, unavailable.reason)
        }
    }

    // MARK: - Providers

    /// Why a provider can't run: a sentence for Settings and a few words for History.
    private struct Unavailable: Error {
        let reason: String
        let note: String
    }

    private struct TestFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func makeClient(for provider: PolishProvider) -> Result<any PolishClient, Unavailable> {
        switch provider {
        case .off:
            return .failure(Unavailable(reason: "AI polish is off.", note: "Polish is off"))

        case .appleIntelligence:
            if let reason = AppleIntelligencePolisher.unavailableReason {
                return .failure(Unavailable(reason: reason, note: AppleIntelligencePolisher.unavailableNote))
            }
            return .success(AppleIntelligencePolisher())

        case .anthropic:
            guard let key = Keychain.string(for: .anthropic) else {
                return .failure(Unavailable(reason: "Add your Anthropic API key to polish with Claude.", note: "No API key"))
            }
            let model = settings.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(AnthropicClient(apiKey: key, model: model.isEmpty ? AnthropicClient.defaultModel : model))

        case .openAICompatible:
            guard let baseURL = endpointURL else {
                return .failure(Unavailable(
                    reason: "Enter the endpoint's base URL, like https://api.openai.com/v1.",
                    note: "Invalid endpoint URL"
                ))
            }
            let model = settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                return .failure(Unavailable(reason: "Enter the name of the model to use.", note: "No model set"))
            }
            let key = Keychain.string(for: .openAICompatible)
            // Ollama, LM Studio and friends on this Mac or the local network don't use keys.
            if key == nil, !Self.isLocal(baseURL) {
                return .failure(Unavailable(reason: "Add the API key for this endpoint.", note: "No API key"))
            }
            return .success(OpenAICompatibleClient(baseURL: baseURL, apiKey: key ?? "", model: model))
        }
    }

    private var endpointURL: URL? {
        let text = settings.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    private static func isLocal(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        if host == "localhost" || host == "::1" || host == "[::1]" || host.hasSuffix(".local") { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 172 && (16...31).contains(octets[1])
    }

    /// The user's setting, kept within sane bounds: a zero or negative value would make polish
    /// always fail, and a huge one would hold every dictation hostage to a stalled server.
    private var timeLimit: Double {
        min(max(settings.polishTimeout, 0.5), 30)
    }

    // MARK: - Messages

    /// A few words for History.
    private static func note(for error: Error, limit: Double) -> String {
        if error is HardDeadline.Exceeded { return "Timed out after \(format(limit)) s" }
        if error is CancellationError { return "Cancelled" }
        if let failure = error as? AppleIntelligencePolisher.Failure { return failure.note }
        if let polishError = error as? PolishError {
            // `if case` rather than a switch: MurmurKit may grow new cases, and those should
            // land on the generic note instead of breaking the build.
            if case .http(let status, _) = polishError {
                switch status {
                case 401, 403: return "API key was rejected"
                case 404: return "Model or endpoint not found"
                case 429: return "Rate limited by the provider"
                case 500...599: return "Provider error (\(status))"
                default: return "Request failed (\(status))"
                }
            }
            if case .missingAPIKey = polishError { return "No API key" }
            if case .timedOut = polishError { return "Timed out after \(format(limit)) s" }
            if case .emptyResponse = polishError { return "The model returned nothing" }
            return "Polish failed"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "Offline"
            case .timedOut: return "Timed out after \(format(limit)) s"
            default: return "Couldn't reach the server"
            }
        }
        return "Polish failed"
    }

    /// A full sentence for the Settings test.
    private static func explanation(for error: Error, limit: Double) -> String {
        if error is HardDeadline.Exceeded {
            return "No reply within \(format(limit)) seconds. Check the endpoint, or raise the polish timeout."
        }
        if let failure = error as? AppleIntelligencePolisher.Failure { return failure.detail }
        if let polishError = error as? PolishError {
            switch polishError {
            case .http(let status, let message) where status == 401 || status == 403:
                return "The API key was rejected (\(status)). \(message)"
            case .http(let status, let message) where status == 404:
                return "The model or endpoint wasn't found (404). Check the model name and base URL. \(message)"
            default:
                return polishError.localizedDescription
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "This Mac is offline."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Couldn't reach the server. Check the base URL."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                return "Couldn't make a secure connection to the server."
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func format(_ seconds: Double) -> String {
        seconds.rounded() == seconds ? String(Int(seconds)) : String(format: "%.1f", seconds)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
