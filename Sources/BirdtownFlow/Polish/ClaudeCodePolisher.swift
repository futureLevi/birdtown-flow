import Foundation
import MurmurKit
import os

/// Polish through Claude Code signed in on this Mac, on the person's own Claude plan.
///
/// **Personal builds only.** Anthropic's terms don't let an app run its users' requests on
/// their Pro or Max logins, so this provider has to come out before Birdtown Flow is sold
/// (see AGENTS.md). Customers use the Anthropic option with their own API key.
///
/// It's fast for two reasons. Every request is stripped down: no tools, settings, plugins or
/// MCP servers, just a short system prompt and the dictation. And Claude Code's second or two
/// of startup happens before anyone is waiting: a session is started ahead of time, answers
/// exactly one dictation, then exits while the next one starts in the background. One
/// dictation per session also means nothing said earlier rides along with the next.
struct ClaudeCodePolisher: PolishClient {
    /// The model and effort measured at about 1.2 s for a 190-word dictation.
    static let defaultModel = "claude-haiku-5-5"
    static let defaultEffort: PolishEffort = .low

    var model = ClaudeCodePolisher.defaultModel
    var effort = ClaudeCodePolisher.defaultEffort

    /// A failure with two phrasings: a few words for History, a sentence for Settings.
    struct Failure: LocalizedError {
        let note: String
        let detail: String
        var errorDescription: String? { detail }

        static let notInstalled = Failure(
            note: "Claude Code isn't installed",
            detail: "Claude Code wasn't found on this Mac. Install it, sign in with your Claude account, then try again."
        )
        static let notSignedIn = Failure(
            note: "Claude Code isn't signed in",
            detail: "Claude Code isn't signed in. Open Terminal, run claude, and sign in with your Claude account."
        )
    }

    func polish(_ request: PolishRequest) async throws -> String {
        try await reply(to: request).text
    }

    /// The answer with Claude Code's own timings, for the Lab.
    func reply(to request: PolishRequest) async throws -> ClaudeCodeReply {
        try await ClaudeCodeSessions.shared.run(
            ClaudeCodeSessionKey(systemPrompt: PolishPrompt.system(for: request), model: model, effort: effort),
            message: PolishPrompt.user(for: request)
        )
    }

    /// Starts a session for the dictation that's about to happen, so it doesn't wait for
    /// Claude Code to launch. Cheap when one is already waiting with the same setup.
    func prewarm(_ request: PolishRequest) {
        let key = ClaudeCodeSessionKey(systemPrompt: PolishPrompt.system(for: request), model: model, effort: effort)
        Task { await ClaudeCodeSessions.shared.prewarm(key) }
    }

    static func shutDown() {
        Task { await ClaudeCodeSessions.shared.shutDown() }
    }
}

/// What a session is started with. A waiting session is only used for a dictation that
/// needs exactly the same.
struct ClaudeCodeSessionKey: Sendable, Equatable {
    var systemPrompt: String
    var model: String
    var effort: PolishEffort
}

/// Claude's answer, and how long it took by Claude Code's own clock.
struct ClaudeCodeReply: Sendable {
    var text: String
    /// Time spent waiting on the model.
    var modelMilliseconds: Int?
    /// Time from the message arriving to the answer, inside Claude Code.
    var sessionMilliseconds: Int?
    /// No session was waiting with this setup, so this answer also waited for Claude Code to start.
    var startedCold = false
}

// MARK: - Sessions

/// Keeps one Claude Code session started and waiting, and hands each dictation to a fresh one.
actor ClaudeCodeSessions {
    static let shared = ClaudeCodeSessions()

    private var spare: ClaudeCodeProcess?
    private var installation: ClaudeCodeLocator.Installation?
    private var lastLookup: ContinuousClock.Instant?

    /// Where Claude Code was found, for Settings. `nil` when it isn't installed.
    func installedPath() async -> String? {
        await locate()?.executable
    }

    /// A session left waiting longer than this is replaced when the next dictation starts,
    /// rather than trusted with a login it read long ago.
    static let maxSpareAge: Duration = .seconds(15 * 60)

    func prewarm(_ key: ClaudeCodeSessionKey) async {
        if let spare, spare.key == key, spare.isRunning, spare.age < Self.maxSpareAge { return }
        spare?.terminate()
        spare = nil
        guard let installation = await locate() else { return }
        spare = try? ClaudeCodeProcess.start(installation: installation, key: key)
    }

    func run(_ key: ClaudeCodeSessionKey, message: String) async throws -> ClaudeCodeReply {
        guard let installation = await locate() else { throw ClaudeCodePolisher.Failure.notInstalled }
        let session: ClaudeCodeProcess
        var cold = false
        if let spare, spare.key == key, spare.isRunning {
            session = spare
        } else {
            // The setup changed (another style's configuration, a Lab test) or nothing was
            // waiting: this one pays the startup.
            spare?.terminate()
            session = try ClaudeCodeProcess.start(installation: installation, key: key)
            cold = true
        }
        spare = nil
        // The dictation goes in first, so starting the next session doesn't hold it up.
        let written = Result { try session.write(message) }
        // The next dictation's session starts now, while this one is answering. Nothing has
        // awaited since `spare` was cleared, so this can't replace one started meanwhile.
        if spare == nil {
            spare = try? ClaudeCodeProcess.start(installation: installation, key: key)
        }

        do {
            try written.get()
            var reply = try await session.awaitReply()
            reply.startedCold = cold
            return reply
        } catch {
            session.terminate()
            throw error
        }
    }

    func shutDown() {
        spare?.terminate()
        spare = nil
    }

    /// Finds Claude Code once, and looks again at most every 30 s while it's missing, so
    /// installing it while the app runs is picked up without a relaunch.
    private func locate() async -> ClaudeCodeLocator.Installation? {
        if let installation { return installation }
        let clock = ContinuousClock()
        if let lastLookup, clock.now - lastLookup < .seconds(30) { return nil }
        lastLookup = clock.now
        installation = await Task.detached(priority: .userInitiated) { ClaudeCodeLocator.find() }.value
        if let installation {
            Log.polish.info("Claude Code found at \(installation.executable, privacy: .public)")
        }
        return installation
    }
}

// MARK: - One process

/// A single `claude -p` session in streaming-JSON mode, used for exactly one message.
///
/// `@unchecked Sendable` is sound because every mutable field is behind `lock`, and the
/// Foundation calls made outside it (writing to the input pipe, reading the output pipe on
/// one background thread, `terminate`, `isRunning`) are thread-safe.
final class ClaudeCodeProcess: @unchecked Sendable {
    let key: ClaudeCodeSessionKey
    private let startedAt = ContinuousClock.now
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let lock = NSLock()
    private var errorText = ""

    private init(process: Process, input: FileHandle, output: FileHandle, key: ClaudeCodeSessionKey) {
        self.process = process
        self.input = input
        self.output = output
        self.key = key
    }

    var isRunning: Bool { process.isRunning }
    var age: Duration { ContinuousClock.now - startedAt }

    static func start(installation: ClaudeCodeLocator.Installation, key: ClaudeCodeSessionKey) throws -> ClaudeCodeProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installation.executable)
        let model = key.model.trimmingCharacters(in: .whitespacesAndNewlines)
        process.arguments = ["-p", "--model", model.isEmpty ? ClaudeCodePolisher.defaultModel : model]
            + (key.effort.value.map { ["--effort", $0] } ?? [])
            + [
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            // Nothing but the instructions and the dictation: no tools, no settings, skills,
            // plugins or MCP servers from this Mac, and nothing saved to disk.
            "--tools", "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--setting-sources", "",
            "--no-session-persistence",
            "--system-prompt", key.systemPrompt,
        ]
        process.environment = installation.environment
        // An empty folder of our own, so no project instructions are picked up from wherever
        // the app happens to be.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BirdtownFlowClaudeCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        process.currentDirectoryURL = folder

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let session = ClaudeCodeProcess(
            process: process, input: stdin.fileHandleForWriting, output: stdout.fileHandleForReading, key: key)
        // Keep a little of what it says on stderr, for the error message if it never answers.
        stderr.fileHandleForReading.readabilityHandler = { [weak session] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            session?.appendError(data)
        }
        try process.run()
        return session
    }

    /// Sends one dictation; `awaitReply` then waits for Claude's answer.
    func write(_ message: String) throws {
        try input.write(contentsOf: Self.userMessageLine(message))
    }

    /// Waits for the answer to what `write` sent.
    func awaitReply() async throws -> ClaudeCodeReply {
        try await withTaskCancellationHandler {
            let event = try await readResult()
            // One message per session: closing the input ends it.
            try? input.close()
            guard !event.isError else { throw Self.failure(for: event.text) }
            let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw PolishError.emptyResponse }
            return ClaudeCodeReply(text: text, modelMilliseconds: event.apiMilliseconds,
                                   sessionMilliseconds: event.milliseconds)
        } onCancel: {
            // A timeout or a cancelled dictation: stop it rather than let it finish unheard.
            self.terminate()
        }
    }

    func terminate() {
        try? input.close()
        if process.isRunning { process.terminate() }
    }

    // MARK: Streaming JSON

    struct ResultEvent: Sendable {
        var isError: Bool
        var text: String
        var milliseconds: Int?
        var apiMilliseconds: Int?
    }

    /// `{"type":"user","message":{"role":"user","content":"…"}}` and a newline.
    static func userMessageLine(_ text: String) throws -> Data {
        let object: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }

    /// The `result` event, if this line is one.
    static func resultEvent(in line: Data) -> ResultEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["type"] as? String == "result"
        else { return nil }
        let isError = (object["is_error"] as? Bool ?? false) || (object["subtype"] as? String ?? "success") != "success"
        let text = object["result"] as? String ?? (object["subtype"] as? String ?? "")
        return ResultEvent(
            isError: isError, text: text,
            milliseconds: (object["duration_ms"] as? NSNumber)?.intValue,
            apiMilliseconds: (object["duration_api_ms"] as? NSNumber)?.intValue)
    }

    private func readResult() async throws -> ResultEvent {
        try await withCheckedThrowingContinuation { continuation in
            // A plain thread blocking on the pipe: it ends when the result arrives or the
            // process exits and the pipe closes.
            let thread = Thread { [self] in
                var buffer = Data()
                while true {
                    let chunk = output.availableData
                    if chunk.isEmpty {
                        continuation.resume(throwing: stoppedFailure())
                        return
                    }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = buffer[buffer.startIndex..<newline]
                        buffer.removeSubrange(buffer.startIndex...newline)
                        if let event = Self.resultEvent(in: Data(line)) {
                            continuation.resume(returning: event)
                            return
                        }
                    }
                }
            }
            thread.name = "Claude Code output"
            thread.start()
        }
    }

    private func appendError(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard errorText.count < 2_000 else { return }
        errorText += String(decoding: data, as: UTF8.self)
    }

    private func stoppedFailure() -> ClaudeCodePolisher.Failure {
        lock.lock()
        let detail = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        if Self.isSignInProblem(detail) { return .notSignedIn }
        Log.polish.error("Claude Code stopped without answering: \(detail, privacy: .public)")
        return ClaudeCodePolisher.Failure(
            note: "Claude Code stopped unexpectedly",
            detail: detail.isEmpty ? "Claude Code stopped without answering." : "Claude Code stopped: \(detail)"
        )
    }

    private static func failure(for message: String) -> ClaudeCodePolisher.Failure {
        if isSignInProblem(message) { return .notSignedIn }
        return ClaudeCodePolisher.Failure(note: "Claude Code failed", detail: "Claude Code couldn't polish this: \(message)")
    }

    static func isSignInProblem(_ message: String) -> Bool {
        let text = message.lowercased()
        return ["not logged in", "/login", "log in", "login expired", "authentication", "oauth"].contains { text.contains($0) }
    }
}

// MARK: - Finding Claude Code

enum ClaudeCodeLocator {
    struct Installation: Sendable, Equatable {
        let executable: String
        /// The login shell's PATH, so an npm-installed `claude` can find `node`.
        let searchPath: String

        var environment: [String: String] {
            let current = ProcessInfo.processInfo.environment
            var environment: [String: String] = ["PATH": searchPath]
            // Only what a login needs. In particular no ANTHROPIC_API_KEY: this provider is
            // the Claude plan, never a key that happens to be in the environment.
            for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "SHELL"] {
                if let value = current[key] { environment[key] = value }
            }
            return environment
        }
    }

    /// Where the installers put it, checked when the login shell doesn't know.
    static var commonPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    }

    static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Blocks for up to a few seconds while the login shell answers; call it off the main thread.
    static func find() -> Installation? {
        let shell = loginShellLookup()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = shell.path ?? "\(home)/.local/bin:\(fallbackPath)"
        let candidates = [shell.executable].compactMap { $0 } + commonPaths
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return Installation(executable: executable, searchPath: path)
    }

    /// Asks the person's login shell for its PATH and for `claude`: apps launched from the
    /// Dock don't inherit the PATH their Terminal sets up.
    private static func loginShellLookup() -> (executable: String?, path: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "printf 'PATH=%s\\n' \"$PATH\"; command -v claude"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (nil, nil)
        }
        // A slow or stuck shell profile mustn't hold this up for long.
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            return (nil, nil)
        }
        let text = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        var executable: String?
        var path: String?
        for line in text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("PATH=") {
                path = String(line.dropFirst(5))
            } else if line.hasPrefix("/"), line.hasSuffix("/claude") {
                executable = line
            }
        }
        return (executable, path)
    }
}
