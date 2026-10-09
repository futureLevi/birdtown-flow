import FluidAudio
import Foundation
import MurmurDictionary
import MurmurKit

/// NVIDIA Parakeet TDT 0.6B (Ultra, v3 or v2), compiled to CoreML and run on the Neural
/// Engine through FluidAudio's `AsrManager`.
///
/// Batch on purpose: at ~100× realtime a 30-second utterance resolves in a few hundred
/// milliseconds after the key is released, and the recording on disk stays the single source
/// of truth for Retry.
actor ParakeetEngine: TranscriptionEngine {
    nonisolated var displayName: String { name }

    private let name: String
    private let manager: AsrManager
    private let booster: VocabularyBooster
    private let boostingEnabled: @Sendable () async -> Bool

    /// One transcription at a time. An actor alone doesn't guarantee that: `transcribe`
    /// suspends while `AsrManager` works, and a second call could start in that gap. The
    /// manager's progress session and shared buffers aren't reentrant, so callers queue here.
    /// A caller cancelled while queued (Esc, a window past its limit) leaves the queue at
    /// once, rather than keep its place for work nobody wants.
    private var busy = false
    private var waiters: [(id: Int, continuation: CheckedContinuation<Void, Error>)] = []
    private var lastWaiterID = 0

    /// FluidAudio rejects anything under 0.3 s (`ASRConstants.minimumAudioDurationSeconds`).
    /// A quick "yes" can be shorter than that, so short clips are padded with silence to a
    /// full second rather than failing; the encoder pads to its 15 s window regardless.
    private static let minimumSamples = 16_000
    private static let sampleRate = 16_000.0
    /// Dictionaries are capped well below this upstream; it only bounds a pathological list.
    private static let maximumBoostTerms = 100

    private init(
        name: String,
        manager: AsrManager,
        booster: VocabularyBooster,
        boostingEnabled: @escaping @Sendable () async -> Bool
    ) {
        self.name = name
        self.manager = manager
        self.booster = booster
        self.boostingEnabled = boostingEnabled
    }

    /// Loads an already-downloaded model and warms it up.
    ///
    /// The warm-up pass matters more than it looks: the first prediction on a freshly loaded
    /// CoreML model pays for ANE program setup and buffer allocation. Paying it here, behind
    /// the "Loading" state, keeps it off the user's first real dictation.
    static func load(
        _ version: AsrModelVersion,
        name: String,
        booster: VocabularyBooster,
        boostingEnabled: @escaping @Sendable () async -> Bool
    ) async throws -> ParakeetEngine {
        let clock = ContinuousClock()
        let started = clock.now
        let models = try await AsrModels.load(from: AsrModels.defaultCacheDirectory(for: version), version: version)
        let manager = AsrManager(config: .default, models: models)
        let engine = ParakeetEngine(name: name, manager: manager, booster: booster, boostingEnabled: boostingEnabled)
        let loaded = clock.now
        try await engine.warmUp()
        // Computed up front: os.Logger wants plain values in its interpolations.
        let loadSeconds = Self.seconds(loaded - started)
        let warmSeconds = Self.seconds(clock.now - loaded)
        Log.speech.info("""
            \(name, privacy: .public) loaded in \(loadSeconds, format: .fixed(precision: 2))s, \
            warmed up in \(warmSeconds, format: .fixed(precision: 2))s
            """)
        return engine
    }

    func transcribe(_ samples: [Float], vocabulary: [String]) async throws -> String {
        try await transcript(samples, vocabulary: vocabulary).text
    }

    func transcript(_ samples: [Float], vocabulary: [String]) async throws -> Transcript {
        guard !samples.isEmpty else { return Transcript(text: "") }

        try await acquire()
        defer { release() }
        try Task.checkCancellation()

        let clock = ContinuousClock()
        let started = clock.now
        let audio = Self.padded(samples)
        let result: ASRResult
        do {
            let layers = await manager.decoderLayerCount
            var decoderState = try TdtDecoderState(decoderLayers: layers)
            result = try await manager.transcribe(audio, decoderState: &decoderState)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // FluidAudio's own messages are written for developers; History shows this one.
            Log.speech.error("\(self.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw ParakeetError.recognitionFailed(name)
        }
        var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let recognized = clock.now
        // Recognition of a long recording takes a while; nobody wants it boosted after Esc.
        try Task.checkCancellation()

        let terms = Self.boostTerms(from: vocabulary)
        var boosted: [AppliedCorrection] = []
        var rescoredText = false
        if !text.isEmpty, !terms.isEmpty, let timings = result.tokenTimings, !timings.isEmpty,
           await boostingEnabled(),
           let rescored = await boost(text: text, timings: timings, audio: audio, terms: terms) {
            text = rescored.text
            boosted = rescored.replacements
            rescoredText = true
        }

        let engineName = name
        let audioSeconds = Double(samples.count) / Self.sampleRate
        let totalSeconds = Self.seconds(clock.now - started)
        let recognitionSeconds = Self.seconds(recognized - started)
        let boostNote = rescoredText ? ", boosted" : ""
        Log.speech.info("""
            \(engineName, privacy: .public): \(audioSeconds, format: .fixed(precision: 1))s audio in \
            \(totalSeconds, format: .fixed(precision: 2))s (recognition \(recognitionSeconds, format: .fixed(precision: 2))s\
            \(boostNote, privacy: .public))
            """)
        return Transcript(text: text, boosted: boosted)
    }

    // MARK: - Boosting

    /// Rescoring runs a second, smaller encoder over the audio. It's bounded so a wedged
    /// CoreML pass can only ever cost the boost, never the dictation.
    private func boost(
        text: String, timings: [TokenTiming], audio: [Float], terms: [String]
    ) async -> VocabularyBooster.Rescored? {
        let booster = self.booster
        let audioSeconds = Double(audio.count) / Self.sampleRate
        let budget = Duration.seconds(TranscriptionTimeLimit.boost(audioSeconds: audioSeconds))
        do {
            return try await HardDeadline.run(within: budget) {
                await booster.rescore(text: text, tokenTimings: timings, samples: audio, terms: terms)
            }
        } catch is CancellationError {
            // The transcription it was for is being thrown away.
            return nil
        } catch {
            Log.speech.info("vocabulary boosting skipped for this dictation (over its time budget)")
            return nil
        }
    }

    /// Trimmed, at least three characters (FluidAudio's own minimum: shorter terms collide with
    /// ordinary words), deduplicated case-insensitively, and sorted so that the same dictionary
    /// always yields the same list and the configured session is reused.
    static func boostTerms(from vocabulary: [String]) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for raw in vocabulary {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.count >= 3, seen.insert(term.lowercased()).inserted else { continue }
            terms.append(term)
            if terms.count == maximumBoostTerms { break }
        }
        return terms.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Helpers

    private func warmUp() async throws {
        let noise = Self.nearSilence(count: Self.minimumSamples)
        let layers = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: layers)
        _ = try await manager.transcribe(noise, decoderState: &decoderState)
    }

    /// Warm-up audio, shared with the boosting model's warm-up. Near-silence rather than exact
    /// zeros: a log-mel front end can take log(0) on digital silence, and the point is to
    /// exercise the real path, not an edge case.
    static func nearSilence(count: Int) -> [Float] {
        var noise = [Float](repeating: 0, count: count)
        var seed: UInt32 = 0x9E37_79B9
        for index in noise.indices {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            noise[index] = (Float(seed >> 8) / Float(1 << 24) - 0.5) * 2e-4
        }
        return noise
    }

    private static func padded(_ samples: [Float]) -> [Float] {
        guard samples.count < minimumSamples else { return samples }
        return samples + [Float](repeating: 0, count: minimumSamples - samples.count)
    }

    /// Waits for the model, in turn. A caller cancelled while it waits gets `CancellationError`
    /// and leaves the queue without the model.
    private func acquire() async throws {
        guard busy else {
            busy = true
            return
        }
        lastWaiterID += 1
        let id = lastWaiterID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Cancelled before it got in line: the handler has already run and found
                // nothing to remove.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// A queued caller was cancelled: it leaves the queue. Nothing to do when `release` has
    /// already handed it the model.
    private func cancelWaiter(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            // Ownership passes straight to the next caller; `busy` stays true. One cancelled
            // a moment ago, before `cancelWaiter` reached it, checks for cancellation before
            // using the model and passes it straight on.
            waiters.removeFirst().continuation.resume()
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

// MARK: - Windows

extension ParakeetEngine: WindowedTranscriptionEngine {
    /// One window of a long recording: decoded in a single model pass, its kept words chosen
    /// by their timings, and those boosted against the window's own audio.
    ///
    /// Behind the same gate as `transcript`, so windows, a Retry and a whole-buffer fallback
    /// never overlap on the model.
    func transcribeWindow(_ request: WindowRequest) async throws -> WindowTranscript {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()

        let clock = ContinuousClock()
        let started = clock.now
        let audio = Self.padded(request.audio)
        let result: ASRResult
        do {
            let layers = await manager.decoderLayerCount
            var decoderState = try TdtDecoderState(decoderLayers: layers)
            result = try await manager.transcribe(audio, decoderState: &decoderState)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.speech.error("""
                \(self.name, privacy: .public) failed on window #\(request.index): \
                \(error.localizedDescription, privacy: .public)
                """)
            throw ParakeetError.recognitionFailed(name)
        }
        let decoded = clock.now
        // The window was given up (Esc, its time limit) while it decoded: don't boost it.
        try Task.checkCancellation()

        // Words are placed by their tokens, so the tokens must spell the text exactly. Both
        // come from the same token ids; anything else is a vocabulary FluidAudio couldn't map.
        let timings = result.tokenTimings ?? []
        let spelled = timings.map(\.token).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard spelled == result.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
            Log.speech.error("window #\(request.index): its token timings don't spell its text")
            throw StitchMismatch()
        }
        let tokens = timings.enumerated().map { index, timing in
            SegmentStitcher.TimedToken(text: timing.token, start: timing.startTime + request.startSeconds, index: index)
        }
        let kept = SegmentStitcher.keep(tokens, in: request.keep, after: request.previous, following: request.following)

        // Only the kept words are offered for rewriting, with their timings on the window's
        // own clock and the window's audio, as `VocabularyBoostingSession` asks of a window
        // cut from a longer stream. The context on either side still informs the CTC pass.
        var text = kept.text
        var boosted: [AppliedCorrection] = []
        let terms = Self.boostTerms(from: request.vocabulary)
        if !kept.text.isEmpty, !terms.isEmpty, await boostingEnabled(),
           let rescored = await boost(
               text: kept.text, timings: kept.tokens.map { timings[$0.index] }, audio: audio, terms: terms
           ) {
            text = rescored.text
            boosted = rescored.replacements
        }

        return WindowTranscript(
            kept: kept,
            text: text,
            boosted: boosted,
            decodeMs: Self.milliseconds(decoded - started),
            boostMs: Self.milliseconds(clock.now - decoded)
        )
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int((seconds(duration) * 1000).rounded())
    }
}

enum ParakeetError: LocalizedError {
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .recognitionFailed(let engine):
            "\(engine) couldn't transcribe this recording. It's saved in History, so you can retry it."
        }
    }
}
