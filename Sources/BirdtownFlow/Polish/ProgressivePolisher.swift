import Foundation
import MurmurKit

/// Polishes the finished parts of a long dictation while the person is still talking, so
/// key-up only waits for the last part. One per dictation session.
///
/// Each time `LiveDictation` commits more text, the text is prepared and split the way key-up
/// will split it (`PolishChunker`, finished parts only), and the first part not yet polished
/// is sent. One at a time, which also keeps Claude Code's single waiting session enough.
/// Results are kept by their exact request, so a part whose text, style or vocabulary is
/// different at key-up is simply polished again then.
@MainActor
final class ProgressivePolisher {
    /// Parts polished so far, by request: the ones the guard accepted, and replies that
    /// can't be used (`PolishService.Outcome.rejected`). A timeout or an error is tried again
    /// at key-up.
    private(set) var cache: [PolishRequest: PolishService.Outcome] = [:]
    /// The part being polished now.
    private(set) var inFlight: (request: PolishRequest, task: Task<PolishService.Outcome, Never>)?

    /// The provider the cached and in-flight results come from; `nil` until the first part
    /// is sent. Key-up uses them only if it polishes with the same one.
    var provider: PolishProvider? { polisher?.provider }

    private let service: PolishService
    private let settings: Settings
    private var template: PolishRequest?
    private var configuration: PolishConfiguration?
    private var options = PipelineOptions()
    /// Made when the first part is ready to send, so a short dictation never reads a key or
    /// builds a client for it.
    private var polisher: (client: any PolishClient, provider: PolishProvider)?
    /// The most recent committed text, for when the part in flight is done.
    private var latest: String?
    /// Parts that timed out or failed while recording; key-up sends them again.
    private var failed: Set<PolishRequest> = []
    private var failuresInARow = 0
    /// Key-up took over, the recording is gone, or the provider keeps failing.
    private var isStopped = false

    /// A provider that fails this many parts in a row is left alone until key-up.
    private static let failureLimit = 2

    init(service: PolishService, settings: Settings) {
        self.service = service
        self.settings = settings
    }

    /// Called once the frontmost context is known; `template.text` is "".
    func configure(template: PolishRequest, configuration: PolishConfiguration?, options: PipelineOptions) {
        guard !isStopped else { return }
        self.template = template
        self.configuration = configuration
        self.options = options
        startNextPart()
    }

    /// The raw text of the windows transcribed so far (`LiveDictation.onCommittedText`).
    func committedTextDidChange(_ raw: String) {
        latest = raw
        startNextPart()
    }

    /// Key-up: `PolishService.polishLong` takes over with `requests`, its parts. Nothing new
    /// starts. The part in flight carries on if it's one of them, for key-up to wait for, and
    /// is cancelled if not (the text changed). The cache stays for key-up to use.
    func stop(keeping requests: [PolishRequest]) {
        isStopped = true
        if let inFlight, !requests.contains(inFlight.request) {
            inFlight.task.cancel()
            self.inFlight = nil
        }
    }

    /// Esc, a discarded recording, or processing is over: stops polishing and forgets results.
    func cancel() {
        isStopped = true
        inFlight?.task.cancel()
        inFlight = nil
        cache = [:]
        latest = nil
    }

    /// Sends the first finished part that hasn't been polished, unless one is in flight.
    private func startNextPart() {
        guard !isStopped, inFlight == nil, settings.polishWhileSpeaking, settings.polishInParts,
              let template, let raw = latest
        else { return }
        let prepared = TextPipeline.prepare(raw, options: options)
        for (index, chunk) in PolishChunker.chunks(prepared, closedOnly: true).enumerated() {
            var request = template
            request.text = chunk.text
            request.context = chunk.context
            request.continues = chunk.continues
            guard cache[request] == nil, !failed.contains(request) else { continue }
            if polisher == nil {
                // No key, Apple Intelligence off…: key-up polishes every part and says why.
                guard let made = service.polisher(using: configuration) else {
                    isStopped = true
                    return
                }
                polisher = made
            }
            guard let polisher else { return }
            start(request, number: index + 1, client: polisher.client, provider: polisher.provider)
            return
        }
    }

    private func start(_ request: PolishRequest, number: Int, client: any PolishClient, provider: PolishProvider) {
        let service = self.service
        let started = ContinuousClock.now
        let deadline = started + .seconds(service.timeLimit)
        let task = Task { [weak self] in
            let outcome = await service.polishOne(request, client: client, provider: provider, deadline: deadline)
            self?.finished(request, outcome: outcome, number: number, elapsed: ContinuousClock.now - started)
            return outcome
        }
        inFlight = (request, task)
    }

    private func finished(_ request: PolishRequest, outcome: PolishService.Outcome, number: Int, elapsed: Duration) {
        // Cancelled, or let go at key-up because the text changed.
        guard inFlight?.request == request else { return }
        inFlight = nil
        let verdict: String
        if outcome.provider != nil || outcome.rejected {
            verdict = outcome.provider != nil ? "accepted" : "rejected"
            cache[request] = outcome
            failuresInARow = 0
        } else {
            verdict = "fell back"
            failed.insert(request)
            failuresInARow += 1
        }
        let words = request.text.split { $0.isWhitespace }.count
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        Log.polish.info(
            "progressive chunk #\(number): \(words) words, \(seconds, format: .fixed(precision: 2))s, \(verdict, privacy: .public)")
        if failuresInARow >= Self.failureLimit {
            Log.polish.info("progressive polish stopped after \(Self.failureLimit) failures in a row")
            isStopped = true
        }
        startNextPart()
    }
}

/// How a dictation's text was polished, for the timing summary (`Log.timing`).
struct PolishReport: Sendable {
    var line = TimingLine("polish")
}
