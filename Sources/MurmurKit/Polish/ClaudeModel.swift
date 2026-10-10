import Foundation

/// What a Claude model takes in a Messages API request, read from its name, for
/// `AnthropicClient`.
///
/// Read from the name rather than looked up in a list, so a model released after this build
/// still gets a request it accepts: a model the rules don't recognise is sent only what
/// every model takes.
enum ClaudeModel {
    /// "claude-sonnet-4-5-20250929" is Sonnet 4.5.
    struct Name: Equatable {
        var family: String
        var major: Int
        var minor: Int
    }

    /// The family and version in a model name, or `nil` for a name that doesn't follow
    /// Anthropic's scheme. Tolerates a platform's prefix ("us.anthropic.claude-…") and a
    /// Vertex snapshot ("claude-opus-4-5@20251101").
    static func name(_ model: String) -> Name? {
        let lowered = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let start = lowered.range(of: "claude-") else { return nil }
        var rest = lowered[start.upperBound...]
        if let at = rest.firstIndex(of: "@") { rest = rest[..<at] }
        let parts = rest.split(separator: "-").map(String.init)
        guard let first = parts.first else { return nil }

        // Names before Claude 4 lead with the version: "claude-3-5-sonnet-20241022".
        if let major = Int(first) {
            guard let family = parts.dropFirst().first(where: { Int($0) == nil }) else { return nil }
            let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            return Name(family: family, major: major, minor: minor)
        }
        guard parts.count > 1, let major = Int(parts[1]) else { return nil }
        // A minor version is one or two digits; eight are a snapshot date: "claude-opus-4-20250514".
        let minor = parts.count > 2 && parts[2].count <= 2 ? Int(parts[2]) ?? 0 : 0
        return Name(family: first, major: major, minor: minor)
    }

    /// Whether the model takes a `temperature` other than its default of 1. Claude Opus 4.7
    /// and later, Sonnet 5 and later, and Haiku 5.5 return a 400 for any other value
    /// (Anthropic's Opus 5.5 migration guide, "Sampling parameters removed"; the Haiku 5.5
    /// guide: "If a request includes `temperature`, it must be `1`"), so only a model known
    /// to take one is sent one. Fable, Mythos and any family not named here are newer than
    /// that change.
    static func acceptsTemperature(_ model: String) -> Bool {
        guard let name = name(model) else { return false }
        switch name.family {
        case "opus": return (name.major, name.minor) < (4, 7)
        case "sonnet", "haiku": return name.major < 5
        default: return false
        }
    }

    /// Whether the model thinks before it answers when a request doesn't set `thinking`.
    /// From Claude 5 on, adaptive thinking is on by default, and its thinking counts toward
    /// `max_tokens` (the Haiku 5.5 migration guide, "Configure thinking"); earlier models
    /// answer straight away unless asked to think.
    static func thinksByDefault(_ model: String) -> Bool {
        guard let name = name(model) else { return false }
        switch name.family {
        case "opus", "sonnet", "haiku": return name.major >= 5
        case "fable", "mythos": return true
        default: return false
        }
    }
}
