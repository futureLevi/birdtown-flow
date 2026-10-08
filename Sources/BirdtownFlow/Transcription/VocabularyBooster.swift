import FluidAudio
import Foundation

/// Dictionary-word boosting for Parakeet: FluidAudio's CTC keyword spotter rescoring the
/// transcript against the audio (`VocabularyBoostingSession`).
///
/// The 0.6B Parakeet models have no CTC head, so this needs the separate Parakeet CTC 110M
/// encoder (about 100 MB, `~/Library/Application Support/FluidAudio/Models/parakeet-ctc-110m-coreml`).
/// Everything here is best-effort by design: until that model is on disk and loaded, or if
/// anything at all goes wrong, `rescore` returns `nil` and the dictation uses the plain
/// transcript. Boosting must never cost the user a dictation, or make one wait for a download.
actor VocabularyBooster {
    private var models: CtcModels?
    private var loading: Task<Void, Never>?
    /// A failed fetch isn't retried on every dictation; offline, that would be a request per
    /// key press.
    private var lastFailure: ContinuousClock.Instant?
    /// Re-tokenizing the terms and rebuilding the rescorer only happens when the list changes.
    private var session: (terms: [String], session: VocabularyBoostingSession)?
    /// The build in progress. Actor methods interleave at every `await`, so without this a
    /// dictation arriving during `prepare(terms:)` would build the same session a second time.
    private var building: (terms: [String], task: Task<VocabularyBoostingSession?, Never>)?
    /// The terms `prepare(terms:)` last asked for, built as soon as the model is loaded.
    private var wantedTerms: [String]?

    private static let retryInterval: Duration = .seconds(120)
    /// A wedged warm-up pass mustn't keep boosting from ever coming on.
    private static let warmUpLimit: Duration = .seconds(30)

    /// Whether the CTC model is on disk, checked without loading it.
    static var isDownloaded: Bool {
        CtcModels.modelsExist(at: CtcModels.defaultCacheDirectory(for: .ctc110m))
    }

    /// Downloads (if needed), loads and warms up the CTC model in the background, then builds
    /// the session for `terms`, so the first dictation with dictionary words pays for none of
    /// it. Returns immediately.
    func prepare(terms: [String]) {
        wantedTerms = terms
        guard models != nil else {
            startLoading()
            return
        }
        buildWantedSession()
    }

    /// The transcript with dictionary terms restored where the audio supports them, or `nil`
    /// when boosting can't run yet or changed nothing.
    ///
    /// - Parameter terms: deduplicated, stably ordered, so an unchanged dictionary reuses the
    ///   configured session.
    func rescore(
        text: String,
        tokenTimings: [TokenTiming],
        samples: [Float],
        terms: [String]
    ) async -> String? {
        guard let models else {
            startLoading()
            return nil
        }

        guard let session = await configuredSession(for: terms, models: models) else { return nil }

        guard
            let output = await session.rescore(text: text, tokenTimings: tokenTimings, audioSamples: samples),
            output.wasModified
        else { return nil }

        let rescored = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return rescored.isEmpty ? nil : rescored
    }

    /// The configured session for `terms`: cached, joined if already being built, or built now.
    private func configuredSession(for terms: [String], models: CtcModels) async -> VocabularyBoostingSession? {
        if let cached = self.session, cached.terms == terms { return cached.session }
        if let building, building.terms == terms { return await building.task.value }

        let task = Task<VocabularyBoostingSession?, Never> {
            do {
                let vocabulary = CustomVocabularyContext(terms: terms.map { CustomVocabularyTerm(text: $0) })
                return try await VocabularyBoostingSession(vocabulary: vocabulary, ctcModels: models)
            } catch {
                Log.speech.error("vocabulary boosting setup failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        building = (terms, task)
        let built = await task.value
        // Another list may have started building meanwhile; that one isn't this one's to clear.
        if self.building?.terms == terms { self.building = nil }
        if let built {
            self.session = (terms, built)
            Log.speech.info("vocabulary boosting configured with \(terms.count, privacy: .public) term(s)")
        }
        return built
    }

    /// Builds the session `prepare(terms:)` asked for, at utility priority. A dictation that
    /// needs it meanwhile joins the build (and lifts its priority) rather than starting another.
    private func buildWantedSession() {
        guard let models, let terms = wantedTerms, !terms.isEmpty else { return }
        Task(priority: .utility) {
            _ = await self.configuredSession(for: terms, models: models)
        }
    }

    private func startLoading() {
        guard models == nil, loading == nil else { return }
        if let lastFailure, ContinuousClock.now - lastFailure < Self.retryInterval { return }

        Log.speech.info("loading the CTC model for vocabulary boosting")
        // Detached at utility priority: a 100 MB fetch and a CoreML compile have no business
        // on this actor's executor or competing with a dictation in progress.
        loading = Task.detached(priority: .utility) {
            do {
                let models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
                // Warmed before it's handed over, so no dictation's boost ever pays for it or
                // shares the Neural Engine with it.
                await Self.warmUp(models)
                await self.didLoad(models)
            } catch {
                await self.didFail(error)
            }
        }
    }

    private func didLoad(_ models: CtcModels) {
        self.models = models
        loading = nil
        Log.speech.info("CTC model ready; dictionary words now boost recognition")
        buildWantedSession()
    }

    /// One throwaway CTC pass over near-silence. As with Parakeet's own warm-up, the first
    /// prediction on a freshly loaded CoreML model pays for ANE program setup and buffer
    /// allocation; paying it here keeps it off the first boosted dictation, where it could
    /// also push the boost past its time budget. Goes straight to the spotter: a rescoring
    /// session returns before the CTC pass when it has no token timings to rescore.
    private static func warmUp(_ models: CtcModels) async {
        let clock = ContinuousClock()
        let started = clock.now
        let spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        let noise = ParakeetEngine.nearSilence(count: 16_000)
        do {
            _ = try await HardDeadline.run(within: warmUpLimit) {
                try await spotter.spotKeywordsWithLogProbs(
                    audioSamples: noise,
                    customVocabulary: CustomVocabularyContext(terms: [])
                )
            }
            let warmSeconds = ParakeetEngine.seconds(clock.now - started)
            Log.speech.info("CTC model warmed up in \(warmSeconds, format: .fixed(precision: 2))s")
        } catch {
            // Best-effort: the first boost pays for it instead, as it always did.
            Log.speech.notice("CTC model warm-up skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func didFail(_ error: Error) {
        loading = nil
        lastFailure = .now
        Log.speech.error("CTC model unavailable, transcribing without boosting: \(error.localizedDescription, privacy: .public)")
    }
}
