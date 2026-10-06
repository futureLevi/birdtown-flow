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

    private static let retryInterval: Duration = .seconds(120)

    /// Whether the CTC model is on disk, checked without loading it.
    static var isDownloaded: Bool {
        CtcModels.modelsExist(at: CtcModels.defaultCacheDirectory(for: .ctc110m))
    }

    /// Downloads (if needed) and loads the CTC model in the background. Returns immediately.
    func prefetch() {
        startLoading()
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

        let session: VocabularyBoostingSession
        if let cached = self.session, cached.terms == terms {
            session = cached.session
        } else {
            do {
                let vocabulary = CustomVocabularyContext(terms: terms.map { CustomVocabularyTerm(text: $0) })
                session = try await VocabularyBoostingSession(vocabulary: vocabulary, ctcModels: models)
                self.session = (terms, session)
                Log.speech.info("vocabulary boosting configured with \(terms.count, privacy: .public) term(s)")
            } catch {
                Log.speech.error("vocabulary boosting setup failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        guard
            let output = await session.rescore(text: text, tokenTimings: tokenTimings, audioSamples: samples),
            output.wasModified
        else { return nil }

        let rescored = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return rescored.isEmpty ? nil : rescored
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
    }

    private func didFail(_ error: Error) {
        loading = nil
        lastFailure = .now
        Log.speech.error("CTC model unavailable, transcribing without boosting: \(error.localizedDescription, privacy: .public)")
    }
}
