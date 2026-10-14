import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Files feedback notes as issues through GitHub's REST API, with a token the person pasted
/// into Settings.
public struct GitHubIssueClient: Sendable {
    /// "owner/name".
    public var repository: GitHubRepository
    public var token: String
    public var timeout: TimeInterval

    public init(repository: GitHubRepository, token: String, timeout: TimeInterval = 15) {
        self.repository = repository
        self.token = token
        self.timeout = timeout
    }

    /// The issue that was opened.
    public struct Created: Equatable, Sendable {
        public var number: Int
        public var url: String
    }

    public func makeRequest(title: String, body: String, labels: [String]) throws -> URLRequest {
        var request = URLRequest(url: repository.issuesURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BirdtownFlow", forHTTPHeaderField: "User-Agent")
        struct Payload: Encodable {
            var title: String
            var body: String
            var labels: [String]?
        }
        request.httpBody = try JSONEncoder().encode(Payload(title: title, body: body, labels: labels.isEmpty ? nil : labels))
        return request
    }

    public static func parseCreated(data: Data, status: Int) throws -> Created {
        guard (200..<300).contains(status) else {
            throw FeedbackSendError.from(status: status, data: data)
        }
        struct Issue: Decodable {
            var number: Int
            var html_url: String
        }
        guard let issue = try? JSONDecoder().decode(Issue.self, from: data) else {
            throw FeedbackSendError.rejected(status: status, message: "GitHub's reply couldn't be read")
        }
        return Created(number: issue.number, url: issue.html_url)
    }

    /// Opens the issue for `note`. A label GitHub won't apply (no permission to create it)
    /// doesn't lose the note: it's filed again without one.
    public func file(_ note: FeedbackNote) async throws -> Created {
        let title = FeedbackIssue.title(for: note)
        let body = FeedbackIssue.body(for: note)
        do {
            return try await send(makeRequest(title: title, body: body, labels: [FeedbackIssue.label]))
        } catch FeedbackSendError.rejected(let status, _) where status == 422 {
            return try await send(makeRequest(title: title, body: body, labels: []))
        }
    }

    private func send(_ request: URLRequest) async throws -> Created {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw FeedbackSendError.offline(error.localizedDescription)
        }
        return try Self.parseCreated(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// A GitHub repository, from whatever the person typed: "owner/name" or its web address.
public struct GitHubRepository: Hashable, Sendable, CustomStringConvertible {
    public var owner: String
    public var name: String

    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www.", "github.com/", "git@github.com:"] where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        while value.hasSuffix("/") { value = String(value.dropLast()) }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let owner = String(parts[0])
        let name = String(parts[1])
        guard !owner.isEmpty, !name.isEmpty,
              owner.unicodeScalars.allSatisfy(allowed.contains),
              name.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        self.owner = owner
        self.name = name
    }

    public var description: String { "\(owner)/\(name)" }

    public var issuesURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/issues")!
    }

    public var webURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)")!
    }
}

/// Why a note wasn't filed, in words Settings can show as they are.
public enum FeedbackSendError: Error, Equatable, Sendable {
    /// No token in Settings yet.
    case notSetUp
    /// The token was refused (expired, revoked, mistyped).
    case unauthorized
    /// The repository doesn't exist, or the token can't see it.
    case repositoryNotFound
    /// No connection, or GitHub didn't answer.
    case offline(String)
    case rejected(status: Int, message: String)

    public var message: String {
        switch self {
        case .notSetUp: "Add a GitHub token in Settings to send feedback"
        case .unauthorized: "GitHub didn't accept the token"
        case .repositoryNotFound: "The feedback repository wasn't found, or the token can't reach it"
        case .offline(let detail): "Couldn't reach GitHub (\(detail))"
        case .rejected(let status, let message): "GitHub said \(status): \(message)"
        }
    }

    /// Worth trying again later without anyone changing anything.
    public var isTransient: Bool {
        switch self {
        case .offline: true
        case .rejected(let status, _): status >= 500 || status == 429
        default: false
        }
    }

    static func from(status: Int, data: Data) -> FeedbackSendError {
        switch status {
        case 401: return .unauthorized
        // GitHub answers 404 for a private repository the token can't see, and 403 for a
        // token without the right scope.
        case 404: return .repositoryNotFound
        default:
            struct Envelope: Decodable { var message: String? }
            let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.message
                ?? String(decoding: data.prefix(200), as: UTF8.self)
            return .rejected(status: status, message: message.isEmpty ? "no details" : message)
        }
    }
}
