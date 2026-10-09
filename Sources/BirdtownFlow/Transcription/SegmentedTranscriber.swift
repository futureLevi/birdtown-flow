import Foundation
import MurmurDictionary
import MurmurKit

/// Decodes a long recording window by window: during recording (`LiveDictation`), so key-up
/// only waits for the last window, and for a Retry of a long WAV, which cuts the same windows.
///
/// Windows are cut by `SegmentPlanner` from WAV-equivalent samples, decoded one at a time by
/// a `WindowedTranscriptionEngine`, and joined by `SegmentStitcher`. Anything that makes the
/// windows doubtful (a failed window, live audio that doesn't match the final buffer) throws
/// `Unavailable`, and `LongTranscription` transcribes the recording whole instead.
actor SegmentedTranscriber {
    /// Why the windows can't be used. `reason` is a fixed token for the log.
    struct Unavailable: Error {
        let reason: String
    }

    /// A window cut from a live recording, not yet decoded: its audio is saved first.
    struct Planned: Sendable {
        let index: Int
        /// The cut it continues from.
        let from: Int
        let cut: SegmentPlanner.Cut
        let window: SegmentWindow
        /// WAV-equivalent samples of `window.audio`.
        let audio: [Float]
        /// Seconds of audio captured past the cut when it was planned: how far behind the
        /// recording the window is.
        let lag: Double
    }

    /// A finished transcription.
    struct Outcome: Sendable {
        var transcript: Transcript
        /// Sub-timings for the summary line (`Log.timing`).
        var line: TimingLine
        /// Each window's text, in order.
        var parts: [String]
        var windows: Int
        var forcedCuts: Int
        /// The longest one window took, decode and boost.
        var slowestWindowMs: Int
    }

    /// For the identity checks at key-up: windows decoded by another engine, or with another
    /// dictionary, aren't used.
    nonisolated let engine: any WindowedTranscriptionEngine
    nonisolated let vocabulary: [String]

    /// A window that takes longer than this gives the windows up.
    static let windowLimit: Duration = .seconds(10)
    private static let sampleRate = 16_000.0

    private let planner = SegmentPlanner()
    private var cuts: [SegmentPlanner.Cut] = []
    private var parts: [WindowTranscript] = []
    private var ledger = SegmentLedger()
    /// The last word kept so far, for the next window's seam check.
    private var previous: SegmentStitcher.TimedWord?
    /// The live windows being decoded, chained one after another.
    private var inFlight: Task<Void, Never>?
    private var decoding = 0
    private var failure: String?
    /// Finishing, given up or cancelled: no more live windows.
    private var isClosed = false
    private var slowestWindowMs = 0

    init(engine: any WindowedTranscriptionEngine, vocabulary: [String]) {
        self.engine = engine
        self.vocabulary = vocabulary
    }

    /// Where the last window's kept stretch ends: everything before it has a window.
    var lastCut: Int { cuts.last?.sample ?? 0 }
    /// The first sample the next window needs.
    var analysisStart: Int { planner.analysisStart(after: lastCut) }
    /// A window is being decoded. A live recording waits for it before cutting the next.
    var isBusy: Bool { decoding > 0 }
    /// Windows decoded so far.
    var committedCount: Int { parts.count }
    /// The decoded windows' text, before boosting, so what's built on it while recording
    /// (`ProgressivePolisher`) doesn't depend on when boosting ran.
    var committedRawText: String {
        SegmentStitcher.join(parts.map {
            SegmentStitcher.Part(leadingPunctuation: $0.kept.leadingPunctuation, text: $0.kept.text)
        })
    }

    // MARK: - Live

    /// The next window, if the audio captured so far can place it. Changes nothing: the
    /// window is only committed by `run`, once its audio is on disk.
    ///
    /// - Parameter raw: samples as captured, from absolute sample `offset` (at or before
    ///   `analysisStart`), quantized here exactly as the WAV will hold them.
    func advance(audio raw: [Float], offset: Int) -> Planned? {
        guard !isClosed, failure == nil else { return nil }
        let from = lastCut
        let start = planner.analysisStart(after: from)
        let needed = planner.analysisEnd(after: from)
        let end = offset + raw.count
        guard offset <= start, end >= needed else { return nil }
        // Only what the cut depends on (the window lies inside it), so a backlog isn't
        // quantized again on every tick.
        let quantized = WAVQuantization.roundTrip(raw[(start - offset)..<(needed - offset)])
        guard let cut = planner.nextCut(after: from, audio: quantized[...], offset: start) else { return nil }
        let window = planner.window(from: from, to: cut.sample, total: end)
        return Planned(
            index: cuts.count + 1,
            from: from,
            cut: cut,
            window: window,
            audio: Array(quantized[(window.audio.lowerBound - start)..<(window.audio.upperBound - start)]),
            lag: Double(end - cut.sample) / Self.sampleRate
        )
    }

    /// Commits a planned window and decodes it in the background, after any still running.
    func run(_ planned: Planned) {
        guard !isClosed, failure == nil, planned.from == lastCut else { return }
        cuts.append(planned.cut)
        ledger.commit(range: planned.window.audio, samples: planned.audio[...])
        decoding += 1
        let prior = inFlight
        inFlight = Task {
            await prior?.value
            await self.decodeLive(planned)
        }
    }

    /// The live recording can't save its audio any more, so no window may be decoded.
    func disable(_ reason: String) {
        isClosed = true
        fail(reason)
    }

    /// The windows won't be used: stop decoding them. Saved audio and rows are the caller's.
    func cancelWork() {
        isClosed = true
        fail("cancelled")
        inFlight?.cancel()
    }

    /// Key-up: the whole recording, as captured. Waits for the window in flight, checks the
    /// windows were cut from this audio, then decodes what's left: any window not cut yet,
    /// and the tail.
    func finish(_ all: [Float]) async throws -> Outcome {
        isClosed = true
        let clock = ContinuousClock()
        let pending = inFlight
        let waitStart = clock.now
        // Esc while waiting stops the window too.
        await withTaskCancellationHandler {
            await pending?.value
        } onCancel: {
            pending?.cancel()
        }
        try Task.checkCancellation()
        let waitMs = Self.milliseconds(waitStart.duration(to: clock.now))
        let liveWindows = parts.count

        if let failure { throw Unavailable(reason: failure) }
        guard ledger.matches(all.lazy.map { WAVQuantization.roundTrip($0) }) else {
            throw Unavailable(reason: "ledgerMismatch")
        }
        let base = analysisStart
        let (catchUpMs, tail) = try await complete(WAVQuantization.roundTrip(all[base...]), base: base, total: all.count)

        var line = TimingLine("transcribe")
        line.count("windows", parts.count)
        line.count("live", liveWindows)
        line.count("forced", forcedCuts)
        line.ms("inflight", waitMs)
        line.ms("catchup", catchUpMs)
        line.ms("tail", tail.ms)
        line.ms("tailBoost", tail.boostMs)
        return outcome(line)
    }

    /// A Retry: the saved WAV, cut and decoded window by window as it was while recording.
    ///
    /// - Parameter samples: as read from the WAV, so already WAV-equivalent.
    static func offline(
        _ samples: [Float], engine: any WindowedTranscriptionEngine, vocabulary: [String]
    ) async throws -> Outcome {
        try await SegmentedTranscriber(engine: engine, vocabulary: vocabulary).transcribeSaved(samples)
    }

    private func transcribeSaved(_ samples: [Float]) async throws -> Outcome {
        isClosed = true
        let (cutMs, tail) = try await complete(samples, base: 0, total: samples.count)
        var line = TimingLine("transcribe")
        line.count("windows", parts.count)
        line.count("forced", forcedCuts)
        line.ms("cut", cutMs)
        line.ms("tail", tail.ms)
        line.ms("tailBoost", tail.boostMs)
        return outcome(line)
    }

    // MARK: - Decoding

    private func decodeLive(_ planned: Planned) async {
        defer { decoding -= 1 }
        guard failure == nil else { return }
        guard !Task.isCancelled else {
            fail("cancelled")
            return
        }
        do {
            _ = try await decode(planned.window, audio: planned.audio, index: planned.index,
                                 cut: planned.cut, lag: planned.lag)
        } catch {
            fail(Self.reason(for: error))
        }
    }

    /// Cuts and decodes every window left in `rest` (WAV-equivalent samples from absolute
    /// sample `base`, at or before `analysisStart`, to the end of a `total`-sample recording),
    /// then the tail. Returns how long the cut windows took, and the tail's time and boost.
    private func complete(
        _ rest: [Float], base: Int, total: Int
    ) async throws -> (cutMs: Int, tail: (ms: Int, boostMs: Int)) {
        let clock = ContinuousClock()
        let cutStart = clock.now
        while let cut = planner.nextCut(after: lastCut, audio: rest[...], offset: base) {
            let window = planner.window(from: lastCut, to: cut.sample, total: total)
            cuts.append(cut)
            let audio = Array(rest[(window.audio.lowerBound - base)..<(window.audio.upperBound - base)])
            _ = try await decodeForResult(window, audio: audio, index: cuts.count, cut: cut)
        }
        let cutMs = Self.milliseconds(cutStart.duration(to: clock.now))

        let tailStart = clock.now
        let window = planner.window(from: lastCut, to: nil, total: total)
        let audio = Array(rest[(window.audio.lowerBound - base)..<(window.audio.upperBound - base)])
        let tail = try await decodeForResult(window, audio: audio, index: cuts.count + 1, cut: nil)
        return (cutMs: cutMs, tail: (ms: Self.milliseconds(tailStart.duration(to: clock.now)), boostMs: tail.boostMs))
    }

    /// `decode`, with any failure but cancellation turned into `Unavailable`.
    private func decodeForResult(
        _ window: SegmentWindow, audio: [Float], index: Int, cut: SegmentPlanner.Cut?
    ) async throws -> WindowTranscript {
        do {
            return try await decode(window, audio: audio, index: index, cut: cut, lag: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Unavailable(reason: Self.reason(for: error))
        }
    }

    /// Decodes one window and keeps its words.
    private func decode(
        _ window: SegmentWindow, audio: [Float], index: Int, cut: SegmentPlanner.Cut?, lag: Double?
    ) async throws -> WindowTranscript {
        let request = WindowRequest(
            audio: audio,
            startSeconds: Double(window.audio.lowerBound) / Self.sampleRate,
            keep: window.keep,
            previous: previous,
            vocabulary: vocabulary,
            index: index
        )
        let engine = self.engine
        let clock = ContinuousClock()
        let started = clock.now
        let part = try await HardDeadline.run(within: Self.windowLimit) {
            try await engine.transcribeWindow(request)
        }
        parts.append(part)
        if let last = part.kept.lastWord { previous = last }
        slowestWindowMs = max(slowestWindowMs, Self.milliseconds(started.duration(to: clock.now)))
        Self.log(part, window: window, index: index, cut: cut, lag: lag)
        return part
    }

    // MARK: - Helpers

    private var forcedCuts: Int {
        cuts.reduce(0) { $0 + ($1.kind == .forced ? 1 : 0) }
    }

    private func fail(_ reason: String) {
        if failure == nil { failure = reason }
    }

    private func outcome(_ line: TimingLine) -> Outcome {
        let text = SegmentStitcher.join(parts.map {
            SegmentStitcher.Part(leadingPunctuation: $0.kept.leadingPunctuation, text: $0.text)
        })
        return Outcome(
            transcript: Transcript(text: text, boosted: Self.merged(parts.map(\.boosted))),
            line: line,
            parts: parts.map(\.text),
            windows: parts.count,
            forcedCuts: forcedCuts,
            slowestWindowMs: slowestWindowMs
        )
    }

    /// Each window's rewrites, one entry per pair, with the counts added.
    private static func merged(_ lists: [[AppliedCorrection]]) -> [AppliedCorrection] {
        var merged: [AppliedCorrection] = []
        for correction in lists.joined() {
            if let index = merged.firstIndex(where: { $0.from == correction.from && $0.to == correction.to }) {
                let seen = merged[index]
                merged[index] = AppliedCorrection(from: seen.from, to: seen.to, count: seen.count + correction.count)
            } else {
                merged.append(correction)
            }
        }
        return merged
    }

    private static func reason(for error: Error) -> String {
        switch error {
        case is StitchMismatch: "stitchMismatch"
        case is CancellationError: "cancelled"
        default: "windowFailed"
        }
    }

    /// `window #12: 14.9s audio, keep 11.6s, cut=pause(0.42s), decode 0.21s, boost 0.12s (+2), lag 1.4s`.
    /// Numbers and fixed tokens only.
    private static func log(
        _ part: WindowTranscript, window: SegmentWindow, index: Int, cut: SegmentPlanner.Cut?, lag: Double?
    ) {
        let audioSeconds = Double(window.audio.count) / sampleRate
        let keepEnd = min(window.keep.upperBound, Double(window.audio.upperBound) / sampleRate)
        let keepSeconds = max(0, keepEnd - window.keep.lowerBound)
        func fixed(_ value: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", value) }
        let cutText: String
        switch cut?.kind {
        case .pause(let frames): cutText = "pause(\(fixed(Double(frames) * 0.02, 2))s)"
        case .forced: cutText = "forced"
        case nil: cutText = "end"
        }
        let rewrites = part.boosted.reduce(0) { $0 + $1.count }
        var message = "window #\(index): \(fixed(audioSeconds, 1))s audio, keep \(fixed(keepSeconds, 1))s, "
            + "cut=\(cutText), decode \(fixed(Double(part.decodeMs) / 1000, 2))s, "
            + "boost \(fixed(Double(part.boostMs) / 1000, 2))s (+\(rewrites))"
        if let lag { message += ", lag \(fixed(lag, 1))s" }
        Log.speech.info("\(message, privacy: .public)")
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
