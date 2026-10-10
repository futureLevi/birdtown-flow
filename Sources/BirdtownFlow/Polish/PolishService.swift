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
        /// The model answered, but its reply can't be used: `PolishGuard` turned it down, or it
        /// was cut off or declined. Asking again with the same request won't help.
        var rejected = false
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

    /// Polishes with Settings' provider, or with a Lab configuration's provider, model and
    /// effort when one is given (its instructions travel in `request.instructions`). Turning
    /// polish off in Settings turns it off for Lab configurations too.
    func polish(_ request: PolishRequest, using configuration: PolishConfiguration? = nil) async -> Outcome {
        let provider = configuration?.provider ?? settings.polishProvider
        let unchanged = Outcome(text: request.text, provider: nil, note: nil)
        guard settings.polishProvider != .off, provider != .off,
              !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return unchanged }

        let client: any PolishClient
        switch makeClient(for: provider, model: configuration?.model, effort: configuration?.effort) {
        case .success(let made):
            client = made
        case .failure(let unavailable):
            Log.polish.info("polish skipped: \(unavailable.note, privacy: .public)")
            return Outcome(text: request.text, provider: nil, note: unavailable.note)
        }
        let limit = oneRequestLimit(for: request.text)
        return await polishOne(
            request, client: client, provider: provider, deadline: ContinuousClock.now + .seconds(limit),
            limit: limit)
    }

    /// One request, finished by `deadline`: the guarded rewrite, or the request's own text
    /// with a note for History. The parts of a long dictation share one deadline (`polishLong`).
    ///
    /// - Parameter limit: how long `deadline` allowed, for the note if it passes; `timeLimit`
    ///   when not given.
    func polishOne(
        _ request: PolishRequest, client: any PolishClient, provider: PolishProvider,
        deadline: ContinuousClock.Instant, limit: Double? = nil
    ) async -> Outcome {
        let clock = ContinuousClock()
        let started = clock.now
        do {
            // A part still queued when time is up isn't sent at all.
            let remaining = deadline - started
            guard remaining > .zero else { throw HardDeadline.Exceeded() }
            let output = try await HardDeadline.run(within: max(remaining, .milliseconds(1))) {
                try await client.polish(request)
            }
            let elapsed = Self.seconds(clock.now - started)
            guard let accepted = PolishGuard.accept(
                output, original: request.text, vocabulary: request.vocabulary, context: request.context
            ) else {
                Log.polish.info("\(provider.rawValue, privacy: .public) rewrite rejected by the guard")
                return Outcome(
                    text: request.text, provider: nil, note: "Rewrite rejected: it changed what was said",
                    rejected: true)
            }
            Log.polish.info("\(provider.rawValue, privacy: .public) polished in \(elapsed, format: .fixed(precision: 2))s")
            return Outcome(text: accepted, provider: provider, note: nil)
        } catch {
            let note = Self.note(for: error, limit: limit ?? timeLimit)
            Log.polish.info("polish fell back (\(provider.rawValue, privacy: .public)): \(note, privacy: .public)")
            return Outcome(text: request.text, provider: nil, note: note, rejected: Self.isUnusableReply(error))
        }
    }

    /// `polish`, for a dictation of any length.
    ///
    /// From `PolishChunker.minimumWords` prepared words on (with `Settings.polishInParts`), the
    /// text is polished in parts at the same time, under one deadline: parts `progressive`
    /// polished while the person talked are reused, the one it's still polishing is awaited,
    /// and the rest are sent in parallel. The deadline grows with the parts left to polish
    /// (`PolishTimeLimit`), up to `overallTimeLimit(for:using:)`. Each part is guarded and falls back
    /// on its own; the note says how many kept their dictated text. Shorter texts go to `polish`.
    func polishLong(
        _ request: PolishRequest, using configuration: PolishConfiguration?, progressive: ProgressivePolisher?
    ) async -> (Outcome, PolishReport) {
        var report = PolishReport()
        let chunks = settings.polishInParts ? PolishChunker.chunks(request.text) : []
        guard chunks.count > 1, let polisher = polisher(using: configuration) else {
            progressive?.stop(keeping: [])
            report.line.count("chunks", 1)
            report.line.seconds("limit", oneRequestLimit(for: request.text))
            return (await polish(request, using: configuration), report)
        }

        let requests = chunks.map { chunk in
            var part = request
            part.text = chunk.text
            part.context = chunk.context
            part.continues = chunk.continues
            return part
        }
        // What was polished while the person talked counts only if it came from this provider,
        // model and endpoint (Settings can change during a recording).
        let identity = clientIdentity(using: configuration)
        let earlier = progressive.flatMap { $0.identity == identity ? $0 : nil }
        progressive?.stop(keeping: earlier == nil ? [] : requests)

        var outcomes = [Outcome?](repeating: nil, count: requests.count)
        var awaited: [(index: Int, task: Task<Outcome, Never>)] = []
        var fresh: [Int] = []
        for (index, part) in requests.enumerated() {
            if let done = earlier?.cache[part] {
                outcomes[index] = done
            } else if let inFlight = earlier?.inFlight, inFlight.request == part {
                awaited.append((index, inFlight.task))
            } else {
                fresh.append(index)
            }
        }
        // The part still in flight counts against the provider's limit, but never holds back
        // the first fresh part.
        let atOnce = concurrency(for: polisher.provider)
        let parallel = min(max(1, atOnce - awaited.count), fresh.count)
        // Only the parts still to polish take time now; cached ones are done.
        let pending = awaited.map { $0.index } + fresh
        let limit = PolishTimeLimit.seconds(
            base: timeLimit, partWords: pending.map { PolishTimeLimit.words(in: requests[$0].text) },
            concurrency: atOnce)
        let deadline = ContinuousClock.now + .seconds(limit)
        let client = polisher.client
        let provider = polisher.provider
        let polishPart: @Sendable (Int) async -> Outcome = { [requests] index in
            await self.polishOne(requests[index], client: client, provider: provider, deadline: deadline, limit: limit)
        }

        let results = await withTaskGroup(of: PartResult.self, returning: [PartResult].self) { group in
            for (index, task) in awaited {
                group.addTask {
                    let started = ContinuousClock.now
                    var outcome = await withTaskCancellationHandler {
                        await task.value
                    } onCancel: {
                        task.cancel()
                    }
                    // It timed out or failed against its own deadline (one request's limit,
                    // set when it was sent): like a part that failed while the person talked,
                    // it gets what's left of this one.
                    if outcome.provider == nil, !outcome.rejected, !Task.isCancelled {
                        outcome = await polishPart(index)
                    }
                    return PartResult(index: index, outcome: outcome, wait: ContinuousClock.now - started)
                }
            }
            var queue = fresh[...]
            for _ in 0..<parallel {
                guard let index = queue.popFirst() else { break }
                group.addTask {
                    let started = ContinuousClock.now
                    let outcome = await polishPart(index)
                    return PartResult(index: index, outcome: outcome, wait: ContinuousClock.now - started)
                }
            }
            var results: [PartResult] = []
            while let result = await group.next() {
                results.append(result)
                // A part finished, awaited or fresh: the next one takes its place.
                if let index = queue.popFirst() {
                    group.addTask {
                        let started = ContinuousClock.now
                        let outcome = await polishPart(index)
                        return PartResult(index: index, outcome: outcome, wait: ContinuousClock.now - started)
                    }
                }
            }
            return results
        }

        for result in results { outcomes[result.index] = result.outcome }
        let parts = zip(requests, outcomes).map { part, outcome in
            outcome ?? Outcome(text: part.text, provider: nil, note: nil)
        }
        let keptAsDictated = parts.count { $0.provider == nil }
        let firstNote = parts.lazy.compactMap(\.note).first
        let outcome: Outcome
        if keptAsDictated == parts.count {
            outcome = Outcome(text: request.text, provider: nil, note: firstNote)
        } else {
            outcome = Outcome(
                text: PolishChunker.join(parts.map(\.text), chunks: chunks, style: request.style),
                provider: provider,
                note: keptAsDictated == 0 ? nil : DictationFeedback.partialPolishNote(
                    keptAsDictated: keptAsDictated, of: parts.count, reason: firstNote ?? ""))
        }

        report.line.count("chunks", parts.count)
        report.line.count("cached", parts.count - awaited.count - fresh.count)
        report.line.count("awaited", awaited.count)
        report.line.count("fresh", fresh.count)
        report.line.count("parallel", parallel)
        report.line.count("fallbacks", keptAsDictated)
        report.line.seconds("limit", limit)
        report.line.ms("slowest", results.map(\.wait).max().map { Self.milliseconds($0) })
        return (outcome, report)
    }

    /// The longest polishing `request` may take, parts and all: `timeLimit` for a normal
    /// dictation, more for a long one (`PolishTimeLimit`). `polishLong` allows it no more than
    /// this, and less when parts were polished while the person talked, so a backstop built
    /// on it (`DictationController`) never cuts polish short. A long text whose provider
    /// can't run gets the one-request limit here but never waits: `polish` returns at once.
    func overallTimeLimit(for request: PolishRequest, using configuration: PolishConfiguration?) -> Double {
        let chunks = settings.polishInParts ? PolishChunker.chunks(request.text) : []
        guard chunks.count > 1 else { return oneRequestLimit(for: request.text) }
        let provider = configuration?.provider ?? settings.polishProvider
        return PolishTimeLimit.seconds(
            base: timeLimit, partWords: chunks.map { PolishTimeLimit.words(in: $0.text) },
            concurrency: concurrency(for: provider))
    }

    /// One request for `text`: `timeLimit`, or more for a long text. A part polished while
    /// the person talks gets the same (`ProgressivePolisher`).
    func oneRequestLimit(for text: String) -> Double {
        PolishTimeLimit.seconds(base: timeLimit, words: PolishTimeLimit.words(in: text))
    }

    /// How many parts `provider` is sent at once.
    private func concurrency(for provider: PolishProvider) -> Int {
        let local = endpointURL.map { Self.isLocal($0) } ?? false
        return PolishChunker.concurrency(for: provider, localEndpoint: local)
    }

    /// One part of `polishLong`, and how long key-up waited for it.
    private struct PartResult: Sendable {
        let index: Int
        let outcome: Outcome
        let wait: Duration
    }

    /// The client a dictation with `configuration` (or Settings) is polished with, and its
    /// provider; `nil` when polish is off or the provider can't run (`polish` notes why).
    func polisher(using configuration: PolishConfiguration?) -> (client: any PolishClient, provider: PolishProvider)? {
        let provider = configuration?.provider ?? settings.polishProvider
        guard settings.polishProvider != .off, provider != .off,
              case .success(let client) = makeClient(
                  for: provider, model: configuration?.model, effort: configuration?.effort)
        else { return nil }
        return (client, provider)
    }

    /// What a client is made from, keys aside: equal identities send text to the same place
    /// and have it polished by the same model the same way.
    struct ClientIdentity: Equatable, Sendable {
        var provider: PolishProvider
        var model: String?
        var effort: PolishEffort?
        /// The OpenAI-compatible base URL; `nil` for the other providers.
        var endpoint: URL?
    }

    /// What a client made now for `configuration` (or Settings) would be made from, as
    /// `makeClient` reads it, without reading a key or making one. A long dictation's parts
    /// polished while the person talks go on, and count at key-up, only while it stays the
    /// same, so a model or endpoint changed in Settings mid-recording gets no more text.
    func clientIdentity(using configuration: PolishConfiguration?) -> ClientIdentity {
        let provider = configuration?.provider ?? settings.polishProvider
        let configured: String? = configuration?.model
        let chosenModel = configured.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let model: String?
        var endpoint: URL?
        switch provider {
        case .anthropic:
            model = chosenModel ?? settings.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAICompatible:
            model = chosenModel ?? settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            endpoint = endpointURL
        case .claudeCode:
            model = chosenModel
        case .off, .appleIntelligence:
            model = nil
        }
        return ClientIdentity(provider: provider, model: model, effort: configuration?.effort, endpoint: endpoint)
    }

    /// Gets the provider ready for a dictation that's starting, while the person talks: loads
    /// Apple's model, or opens the connection to a cloud endpoint. `request` has everything but
    /// the text. Claude Code is started by `ClaudeCodePolisher.prewarm` instead. Reads no keys,
    /// sends none, and never changes what polish returns.
    func prewarm(_ request: PolishRequest, using configuration: PolishConfiguration? = nil) {
        guard settings.polishProvider != .off else { return }
        switch configuration?.provider ?? settings.polishProvider {
        case .appleIntelligence:
            AppleIntelligencePolisher.prewarm(request)
        case .anthropic:
            AnthropicClient.preconnect()
        case .openAICompatible:
            if let endpointURL { OpenAICompatibleClient.preconnect(baseURL: endpointURL) }
        case .off, .claudeCode:
            break
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
            vocabulary: [],
            level: settings.polishLevel
        )
        let limit = max(timeLimit, Self.testTimeLimit)
        do {
            let output = try await HardDeadline.run(within: .seconds(limit)) {
                try await client.polish(request)
            }
            guard let accepted = PolishGuard.accept(output, original: request.text, vocabulary: request.vocabulary) else {
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
        return availability(of: provider)
    }

    /// The same for any provider, for the Lab.
    func availability(of provider: PolishProvider) -> (available: Bool, reason: String?) {
        switch makeClient(for: provider) {
        case .success:
            return (true, nil)
        case .failure(let unavailable):
            return (false, unavailable.reason)
        }
    }

    // MARK: - Lab

    /// How one Lab configuration did on one piece of text.
    struct LabResult: Sendable {
        enum Verdict: Sendable, Equatable {
            /// The guard accepted the rewrite; this is what dictation would use.
            case accepted(String)
            /// The model replied, but the guard would have kept the original.
            case rejected(reply: String, reason: String)
            /// No usable reply: an error, a missing key, a timeout.
            case failed(String)
        }

        var verdict: Verdict
        /// From sending to the answer, as dictation would wait for it.
        var totalMilliseconds: Int
        /// Claude Code only: time spent on the model, and in Claude Code overall.
        var modelMilliseconds: Int?
        var sessionMilliseconds: Int?
        /// Claude Code only: the session had to start first, which dictation does ahead of time.
        var startedCold = false
    }

    /// The Lab's longest wait: long enough to see how slow a slow setup is.
    static let labTimeLimit: Double = 60

    /// Runs one configuration on `request` the way dictation would, but with a long time
    /// limit, and reports the guard's verdict and the timings instead of falling back.
    func labRun(_ configuration: PolishConfiguration, request: PolishRequest) async -> LabResult {
        var request = request
        request.instructions = configuration.instructions
        let client: any PolishClient
        switch makeClient(for: configuration.provider, model: configuration.model, effort: configuration.effort) {
        case .success(let made):
            client = made
        case .failure(let unavailable):
            return LabResult(verdict: .failed(unavailable.reason), totalMilliseconds: 0)
        }

        let clock = ContinuousClock()
        let started = clock.now
        let limit = Self.labTimeLimit
        do {
            let request = request
            let reply: ClaudeCodeReply = try await HardDeadline.run(within: .seconds(limit)) {
                if let claude = client as? ClaudeCodePolisher {
                    return try await claude.reply(to: request)
                }
                return ClaudeCodeReply(text: try await client.polish(request))
            }
            let total = Self.milliseconds(clock.now - started)
            let verdict: LabResult.Verdict =
                switch PolishGuard.review(reply.text, original: request.text, vocabulary: request.vocabulary) {
                case .accepted(let text): .accepted(text)
                case .rejected(let rejection): .rejected(reply: reply.text, reason: rejection.reason)
                }
            return LabResult(
                verdict: verdict, totalMilliseconds: total, modelMilliseconds: reply.modelMilliseconds,
                sessionMilliseconds: reply.sessionMilliseconds, startedCold: reply.startedCold)
        } catch {
            let message = error is CancellationError ? "Stopped before it finished." : Self.explanation(for: error, limit: limit)
            return LabResult(verdict: .failed(message), totalMilliseconds: Self.milliseconds(clock.now - started))
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

    /// A client for `provider`. `model` and `effort` come from a Lab configuration; without
    /// them, Settings decides.
    private func makeClient(
        for provider: PolishProvider, model: String? = nil, effort: PolishEffort? = nil
    ) -> Result<any PolishClient, Unavailable> {
        // A configuration with no model named uses the one in Settings.
        let chosenModel = model.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
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
            let model = chosenModel ?? settings.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(AnthropicClient(
                apiKey: key, model: model.isEmpty ? AnthropicClient.defaultModel : model, effort: effort))

        case .openAICompatible:
            guard let baseURL = endpointURL else {
                return .failure(Unavailable(
                    reason: "Enter the endpoint's base URL, like https://api.openai.com/v1.",
                    note: "Invalid endpoint URL"
                ))
            }
            let model = chosenModel ?? settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                return .failure(Unavailable(reason: "Enter the name of the model to use.", note: "No model set"))
            }
            let key = Keychain.string(for: .openAICompatible)
            // Ollama, LM Studio and friends on this Mac or the local network don't use keys.
            if key == nil, !Self.isLocal(baseURL) {
                return .failure(Unavailable(reason: "Add the API key for this endpoint.", note: "No API key"))
            }
            return .success(OpenAICompatibleClient(baseURL: baseURL, apiKey: key ?? "", model: model))

        case .claudeCode:
            // Whether it's installed and signed in is only known by trying; the polisher
            // reports either problem in its own words.
            return .success(Self.claudeCode(model: chosenModel, effort: effort))
        }
    }

    /// Claude Code with a configuration's model and effort, or the defaults.
    static func claudeCode(model: String?, effort: PolishEffort?) -> ClaudeCodePolisher {
        var polisher = ClaudeCodePolisher()
        if let model, !model.isEmpty { polisher.model = model }
        if let effort { polisher.effort = effort }
        return polisher
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

    /// The user's setting, kept within sane bounds (`PolishTimeLimit.base`): the limit for a
    /// normal dictation. A zero or negative value would make polish always fail, and a huge one
    /// would hold every dictation hostage to a stalled server.
    var timeLimit: Double {
        PolishTimeLimit.base(settings.polishTimeout)
    }

    // MARK: - Messages

    /// The model replied, but cut off or declining: the same request would get much the same
    /// reply, so it isn't sent again.
    private static func isUnusableReply(_ error: Error) -> Bool {
        guard let polishError = error as? PolishError else { return false }
        // `if case`, as in `note(for:limit:)`: a new MurmurKit case is simply worth a retry.
        if case .truncated = polishError { return true }
        if case .refused = polishError { return true }
        return false
    }

    /// A few words for History.
    private static func note(for error: Error, limit: Double) -> String {
        if error is HardDeadline.Exceeded { return "Timed out after \(format(limit)) s" }
        if error is CancellationError { return "Cancelled" }
        if let failure = error as? AppleIntelligencePolisher.Failure { return failure.note }
        if let failure = error as? ClaudeCodePolisher.Failure { return failure.note }
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
            if case .truncated = polishError { return "The reply was cut off" }
            if case .refused = polishError { return "The model declined to edit it" }
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
        if let failure = error as? ClaudeCodePolisher.Failure { return failure.detail }
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

    private static func milliseconds(_ duration: Duration) -> Int {
        Int((seconds(duration) * 1000).rounded())
    }
}
