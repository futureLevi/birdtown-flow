import Foundation

/// How one dictation's polish went, beyond how long it took: what it was sent to and, for
/// Claude Code, where the time went. History keeps part of it (`DictationTimings`) and the
/// timing summary all of it (`addFields(to:)`).
///
/// Every field is `nil` when it wasn't measured: only Claude Code reports its own timings,
/// and Apple Intelligence names no model.
public struct PolishDiagnostics: Sendable, Hashable {
    /// The model and effort the request went out with, e.g. `AnthropicClient.defaultModel`
    /// and "low". No effort when the provider picks its own.
    public var model: String?
    public var effort: String?
    /// Claude Code: no session was waiting with this setup, so the request also waited for
    /// Claude Code to start.
    public var startedCold: Bool?
    /// Claude Code: why it started cold, a fixed token ("noSpare", "differentSetup", "spareExited").
    public var coldReason: String?
    /// Claude Code: time spent waiting on the model (its `duration_api_ms`)…
    public var modelMs: Int?
    /// …and from the message arriving to the answer, inside Claude Code (`duration_ms`).
    public var sessionMs: Int?
    /// Claude Code: how long the waiting session had been running when it took the request.
    /// Less than Claude Code's startup means it was still starting.
    public var spareAgeMs: Int?
    /// Polish in parts: how many of the parts key-up polished or waited for started cold.
    public var coldParts: Int?

    public init(
        model: String? = nil, effort: String? = nil, startedCold: Bool? = nil, coldReason: String? = nil,
        modelMs: Int? = nil, sessionMs: Int? = nil, spareAgeMs: Int? = nil, coldParts: Int? = nil
    ) {
        self.model = model
        self.effort = effort
        self.startedCold = startedCold
        self.coldReason = coldReason
        self.modelMs = modelMs
        self.sessionMs = sessionMs
        self.spareAgeMs = spareAgeMs
        self.coldParts = coldParts
    }

    /// A long dictation polished in parts (`PolishChunker`), from the parts key-up polished
    /// or waited for. They ran side by side, so the slowest model and session times are the
    /// ones key-up felt; it started cold if any of them did. Parts polished while the person
    /// talked aren't passed in: they cost key-up nothing. Every part goes to the same model,
    /// so `model` and `effort` are given once.
    public static func parts(_ waitedFor: [PolishDiagnostics], model: String?, effort: String?) -> PolishDiagnostics {
        let reported = waitedFor.compactMap(\.startedCold)
        let cold = waitedFor.filter { $0.startedCold == true }
        return PolishDiagnostics(
            model: model,
            effort: effort,
            startedCold: reported.isEmpty ? nil : !cold.isEmpty,
            coldReason: cold.lazy.compactMap(\.coldReason).first,
            modelMs: waitedFor.compactMap(\.modelMs).max(),
            sessionMs: waitedFor.compactMap(\.sessionMs).max(),
            coldParts: reported.isEmpty ? nil : cold.count
        )
    }

    /// Appends what was measured to a dictation's timing summary, after its `polish=` time:
    /// `polishCold=1 polishColdReason=differentSetup polishModel=1180ms polishSession=1402ms
    /// polishModelName=<model> polishEffort=low`.
    public func addFields(to line: inout TimingLine) {
        if let startedCold { line.count("polishCold", startedCold ? 1 : 0) }
        if let coldReason { line.tag("polishColdReason", Self.token(coldReason)) }
        if let coldParts { line.count("polishColdParts", coldParts) }
        line.ms("polishModel", modelMs)
        line.ms("polishSession", sessionMs)
        line.ms("polishSpareAge", spareAgeMs)
        if let model { line.tag("polishModelName", Self.token(model)) }
        if let effort { line.tag("polishEffort", Self.token(effort)) }
    }

    /// A model name typed in the Lab or Settings as one key=value token: anything but ASCII
    /// letters, digits and `-_.:/@` becomes `_`, so the summary line still splits on spaces.
    static func token(_ text: String) -> String {
        let allowed = Set("-_.:/@")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = String(trimmed.map { (character: Character) -> Character in
            let kept = character.isASCII && (character.isLetter || character.isNumber || allowed.contains(character))
            return kept ? character : "_"
        })
        return cleaned.isEmpty ? "_" : cleaned
    }
}

extension DictationTimings {
    /// Takes History's share of `diagnostics`: the model's time, a cold start, the model and
    /// its effort. `nil` (polish didn't run) clears them, as a Retry without polish should.
    public mutating func setPolish(_ diagnostics: PolishDiagnostics?) {
        polishModelMs = diagnostics?.modelMs
        polishStartedCold = diagnostics?.startedCold
        polishModel = diagnostics?.model
        polishEffort = diagnostics?.effort
    }

    /// What History's Timings view says after polish's time, in order: "cold start", the
    /// model's own time ("model 1,180 ms", in `format`), and the model with its effort
    /// ("<model> low"). Empty when none of it was recorded.
    public func polishDetails(format: (Int) -> String) -> [String] {
        var details: [String] = []
        if polishStartedCold == true { details.append("cold start") }
        if let polishModelMs { details.append("model \(format(polishModelMs))") }
        let sentWith = [polishModel, polishEffort].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !sentWith.isEmpty { details.append(sentWith) }
        return details
    }
}
