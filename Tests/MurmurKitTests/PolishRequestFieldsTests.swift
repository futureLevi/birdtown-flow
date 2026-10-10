import Foundation
import Testing
@testable import MurmurKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func dictation() -> PolishRequest {
    PolishRequest(text: "um so I think we should uh go", style: .casual, category: .work, appName: "Slack", vocabulary: [])
}

private func body(_ urlRequest: URLRequest) throws -> [String: Any] {
    let data = try #require(urlRequest.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("Claude models")
struct ClaudeModelTests {
    @Test("Names are read whatever the scheme, platform prefix or snapshot", arguments: [
        ("claude-haiku-5-5", "haiku", "5.5"),
        ("claude-sonnet-4-5-20250929", "sonnet", "4.5"),
        ("claude-opus-4-20250514", "opus", "4.0"),
        ("claude-opus-4-1", "opus", "4.1"),
        ("claude-fable-5", "fable", "5.0"),
        ("claude-3-5-haiku-20241022", "haiku", "3.5"),
        ("claude-3-opus-20240229", "opus", "3.0"),
        ("us.anthropic.claude-sonnet-4-6-v1:0", "sonnet", "4.6"),
        ("claude-opus-4-5@20251101", "opus", "4.5"),
        (" Claude-Haiku-6 ", "haiku", "6.0"),
    ])
    func names(model: String, family: String, version: String) throws {
        let name = try #require(ClaudeModel.name(model))
        #expect(name.family == family)
        #expect("\(name.major).\(name.minor)" == version)
    }

    @Test("Other names aren't read", arguments: ["gpt-4.1-mini", "", "claude-", "claude-next", "claude-3"])
    func otherNames(model: String) {
        #expect(ClaudeModel.name(model) == nil)
    }

    @Test("Temperature goes only to models known to take one", arguments: [
        ("claude-haiku-4-5", true), ("claude-haiku-4-5-20251001", true), ("claude-sonnet-4-6", true),
        ("claude-sonnet-4-5-20250929", true), ("claude-opus-4-6", true), ("claude-opus-4-1", true),
        ("claude-opus-4-20250514", true), ("claude-3-5-haiku-20241022", true), ("claude-3-opus-20240229", true),
        ("claude-opus-4-7", false), ("claude-opus-4-8", false), ("claude-opus-5", false), ("claude-opus-5-5", false),
        ("claude-sonnet-5", false), ("claude-sonnet-5-5", false), ("claude-haiku-5-5", false),
        ("claude-fable-5-1", false), ("claude-mythos-5-1", false),
        // Newer than this build: left at the default every model takes.
        ("claude-haiku-6", false), ("claude-sonata-1", false), ("my-proxy-model", false), ("", false),
    ])
    func temperature(model: String, accepts: Bool) {
        #expect(ClaudeModel.acceptsTemperature(model) == accepts)
    }

    @Test("Claude 5 and later think before they answer unless told otherwise", arguments: [
        ("claude-haiku-5-5", true), ("claude-sonnet-5", true), ("claude-sonnet-5-5", true), ("claude-opus-5", true),
        ("claude-opus-5-5", true), ("claude-fable-5-1", true), ("claude-mythos-5-1", true), ("claude-haiku-6", true),
        ("claude-haiku-4-5", false), ("claude-sonnet-4-6", false), ("claude-opus-4-8", false),
        ("claude-3-5-haiku-latest", false), ("claude-sonata-1", false), ("gpt-oss-20b", false),
    ])
    func thinking(model: String, thinks: Bool) {
        #expect(ClaudeModel.thinksByDefault(model) == thinks)
    }
}

@Suite("Polish request fields")
struct PolishRequestFieldsTests {
    // MARK: Anthropic

    @Test("Anthropic: temperature 0 only for models that take one, and none for the rest")
    func anthropicTemperature() throws {
        func temperature(_ model: String) throws -> Any? {
            try body(AnthropicClient(apiKey: "k", model: model).makeRequest(for: dictation()))["temperature"]
        }
        #expect(try temperature("claude-haiku-5-5") == nil)
        #expect(try temperature("claude-sonnet-5-5") == nil)
        #expect(try temperature("claude-opus-4-7") == nil)
        #expect(try temperature("claude-haiku-4-5") as? Double == 0)
        #expect(try temperature("claude-sonnet-4-6") as? Double == 0)
    }

    @Test("Anthropic: models that think are asked for low effort, and get room to think at any other")
    func anthropicThinkingBudget() throws {
        func sent(_ model: String, _ effort: PolishEffort? = nil) throws -> [String: Any] {
            try body(AnthropicClient(apiKey: "k", model: model, effort: effort).makeRequest(for: dictation()))
        }
        let reply = PolishPrompt.maxTokens(for: dictation().text)
        for model in ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"] {
            let automatic = try sent(model)
            #expect((automatic["output_config"] as? [String: Any])?["effort"] as? String == "low")
            #expect(automatic["max_tokens"] as? Int == reply)
        }
        #expect(try sent("claude-haiku-5-5", .low)["max_tokens"] as? Int == reply)
        // The model's own default (medium or high) and anything above low may think at length.
        for effort in [PolishEffort.standard, .medium, .high, .max] {
            #expect(try sent("claude-haiku-5-5", effort)["max_tokens"] as? Int == reply + AnthropicClient.thinkingAllowance)
        }
        // Models that don't think unless asked keep the reply's budget and their own effort.
        let older = try sent("claude-opus-4-8")
        #expect(older["output_config"] == nil)
        #expect(older["max_tokens"] as? Int == reply)
        #expect(try sent("claude-haiku-4-5", .high)["max_tokens"] as? Int == reply)
    }

    // MARK: OpenAI-compatible

    private func makeClient(effort: PolishEffort? = nil, model: String = "gpt-oss-20b") -> OpenAICompatibleClient {
        // An endpoint of its own, so what one test's server turned down can't leak into another's.
        OpenAICompatibleClient(
            baseURL: URL(string: "https://\(UUID().uuidString.lowercased()).example.com/v1")!, apiKey: "k",
            model: model, effort: effort)
    }

    @Test("OpenAI-compatible: the picked effort is sent as reasoning_effort", arguments: [
        (PolishEffort.low, "low"), (.medium, "medium"), (.high, "high"), (.max, "high"),
    ])
    func reasoningEffort(effort: PolishEffort, value: String) throws {
        let sent = try body(makeClient(effort: effort).makeRequest(for: dictation()))
        #expect(sent["reasoning_effort"] as? String == value)
        #expect(sent["temperature"] as? Double == 0)
    }

    @Test("OpenAI-compatible: no effort picked, no reasoning_effort")
    func noReasoningEffort() throws {
        #expect(try body(makeClient().makeRequest(for: dictation()))["reasoning_effort"] == nil)
        #expect(try body(makeClient(effort: .standard).makeRequest(for: dictation()))["reasoning_effort"] == nil)
    }

    @Test("OpenAI-compatible: either field can be left out on its own")
    func leavingOut() throws {
        let medium = makeClient(effort: .medium)
        let withoutEffort = try body(medium.makeRequest(for: dictation(), leavingOut: [.reasoningEffort]))
        #expect(withoutEffort["reasoning_effort"] == nil)
        #expect(withoutEffort["temperature"] as? Double == 0)
        let withoutTemperature = try body(medium.makeRequest(for: dictation(), leavingOut: [.temperature]))
        #expect(withoutTemperature["temperature"] == nil)
        #expect(withoutTemperature["reasoning_effort"] as? String == "medium")
    }

    @Test("A 400 drops the fields it names, or else reasoning_effort")
    func fieldsToDrop() {
        typealias Fields = Set<OpenAICompatibleClient.OptionalField>
        let temperature: Fields = [.temperature]
        let effort: Fields = [.reasoningEffort]
        let both = temperature.union(effort)
        func drop(_ message: String, sent: Fields) -> Fields {
            OpenAICompatibleClient.fieldsToDrop(afterRejection: message, sent: sent)
        }
        #expect(drop(temperatureRejection, sent: both) == temperature)
        #expect(drop(effortRejection, sent: both) == effort)
        #expect(drop("Reasoning effort must be one of none, default", sent: both) == effort)
        #expect(drop("Extra inputs are not permitted", sent: both) == effort)
        // Without reasoning_effort, a 400 that names nothing we sent stands, as it always did.
        #expect(drop("Extra inputs are not permitted", sent: temperature).isEmpty)
        #expect(drop(effortRejection, sent: temperature).isEmpty)
        #expect(drop("temperature and reasoning_effort are not supported", sent: both) == both)
    }

    @Test("A server that doesn't know reasoning_effort is asked again without it, and later dictations leave it out")
    func effortRetry() async throws {
        let client = makeClient(effort: .low, model: "llama-3.3-70b-versatile")
        let server = FakeServer([(400, errorBody(effortRejection)), (200, finished)])
        let text = try await client.polish(dictation(), send: server.send)
        #expect(text == "So I think we should go.")
        #expect(server.sent.count == 2)
        #expect(server.sent[0]["reasoning_effort"] as? String == "low")
        #expect(server.sent[1]["reasoning_effort"] == nil)
        #expect(server.sent[1]["temperature"] as? Double == 0)

        let later = FakeServer([(200, finished)])
        _ = try await client.polish(dictation(), send: later.send)
        #expect(later.sent.count == 1)
        #expect(later.sent[0]["reasoning_effort"] == nil)
    }

    @Test("A temperature rejection drops only the temperature; the effort stays")
    func temperatureRetryKeepsEffort() async throws {
        let client = makeClient(effort: .medium, model: "gpt-5-mini")
        let server = FakeServer([(400, errorBody(temperatureRejection)), (200, finished)])
        _ = try await client.polish(dictation(), send: server.send)
        #expect(server.sent.count == 2)
        #expect(server.sent[1]["temperature"] == nil)
        #expect(server.sent[1]["reasoning_effort"] as? String == "medium")
    }

    @Test("Each rejection takes one more field off, and then the request stops changing")
    func retriesOneFieldAtATime() async throws {
        let client = makeClient(effort: .high)
        let server = FakeServer([(400, errorBody(temperatureRejection)), (400, errorBody(effortRejection)), (200, finished)])
        _ = try await client.polish(dictation(), send: server.send)
        #expect(server.sent.count == 3)
        #expect(server.sent[2]["temperature"] == nil)
        #expect(server.sent[2]["reasoning_effort"] == nil)

        let stubborn = FakeServer([(400, errorBody(temperatureRejection)), (400, errorBody(effortRejection)), (400, errorBody("No"))])
        do {
            _ = try await makeClient(effort: .high).polish(dictation(), send: stubborn.send)
            Issue.record("Expected the last 400 to stand")
        } catch let PolishError.http(status, message) {
            #expect(status == 400)
            #expect(message == "No")
        }
        #expect(stubborn.sent.count == 3)
    }

    @Test("A 400 that names nothing stands when there's no effort to drop")
    func unrelatedRejectionStands() async throws {
        let server = FakeServer([(400, errorBody("This model's maximum context length is 8192 tokens"))])
        do {
            _ = try await makeClient().polish(dictation(), send: server.send)
            Issue.record("Expected the 400 to stand")
        } catch let PolishError.http(status, message) {
            #expect(status == 400)
            #expect(message.contains("context length"))
        }
        #expect(server.sent.count == 1)
    }

    @Test("A guess that didn't help isn't remembered")
    func failedGuessForgotten() async throws {
        let client = makeClient(effort: .high)
        let server = FakeServer([(400, errorBody("Bad request")), (400, errorBody("Bad request"))])
        do {
            _ = try await client.polish(dictation(), send: server.send)
            Issue.record("Expected the 400 to stand")
        } catch let PolishError.http(status, _) {
            #expect(status == 400)
        }
        #expect(server.sent.count == 2)
        #expect(server.sent[1]["reasoning_effort"] == nil)

        let later = FakeServer([(200, finished)])
        _ = try await client.polish(dictation(), send: later.send)
        #expect(later.sent[0]["reasoning_effort"] as? String == "high")
    }

    // MARK: Lab

    @Test("The Lab offers OpenAI-compatible endpoints the effort levels reasoning_effort has")
    func labEffortOptions() {
        #expect(PolishConfiguration.effortOptions(for: .anthropic) == PolishEffort.allCases)
        #expect(PolishConfiguration.effortOptions(for: .claudeCode) == PolishEffort.allCases)
        #expect(PolishConfiguration.effortOptions(for: .openAICompatible) == [PolishEffort.standard, .low, .medium, .high])
        #expect(PolishConfiguration.effortOptions(for: .appleIntelligence).isEmpty)

        var config = PolishConfiguration.starters()[0]
        config.provider = .openAICompatible
        config.model = "gpt-oss-20b"
        #expect(config.usesEffort)
        #expect(config.summary == "OpenAI-compatible · gpt-oss-20b · Low effort")
        config.provider = .appleIntelligence
        #expect(!config.usesEffort)
    }

    @Test("An effort a provider doesn't offer becomes the nearest one it does")
    func labEffortClamp() throws {
        #expect(PolishConfiguration.effort(.max, offeredBy: .openAICompatible) == .high)
        #expect(PolishConfiguration.effort(.medium, offeredBy: .openAICompatible) == .medium)
        #expect(PolishConfiguration.effort(.max, offeredBy: .anthropic) == .max)
        #expect(PolishConfiguration.effort(.max, offeredBy: .appleIntelligence) == .max)

        let json = """
            {"configurations":[{"id":"\(UUID().uuidString)","name":"Groq","provider":"openAICompatible",\
            "model":"gpt-oss-20b","effort":"max","instructions":""}]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PolishLabState.self, from: Data(json.utf8))
        #expect(state.configurations.first?.effort == PolishEffort.high)
    }
}

// MARK: - A pretend server

private let finished = #"{"choices":[{"message":{"role":"assistant","content":"So I think we should go."},"finish_reason":"stop"}]}"#
private let temperatureRejection =
    "Unsupported value: 'temperature' does not support 0 with this model. Only the default (1) value is supported."
private let effortRejection = "Unsupported parameter: 'reasoning_effort' is not supported with this model."

/// `{"error":{"message":…}}`, the way OpenAI-compatible servers explain a 400.
private func errorBody(_ message: String) -> String {
    struct Envelope: Encodable {
        struct Detail: Encodable { var message: String }
        var error: Detail
    }
    let data = try? JSONEncoder().encode(Envelope(error: .init(message: message)))
    return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
}

/// Plays an OpenAI-compatible server: answers each request with the next reply, and keeps
/// the body of each request it was sent.
private final class FakeServer {
    private var replies: [(status: Int, body: String)]
    private(set) var sent: [[String: Any]] = []

    init(_ replies: [(status: Int, body: String)]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try sent.append(body(request))
        guard !replies.isEmpty else { return (Data(), 500) }
        let reply = replies.removeFirst()
        return (Data(reply.body.utf8), reply.status)
    }
}
