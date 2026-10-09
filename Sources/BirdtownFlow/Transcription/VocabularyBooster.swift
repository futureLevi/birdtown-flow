import FluidAudio
import Foundation
import MurmurDictionary
import MurmurKit

/// Dictionary-word boosting for Parakeet: FluidAudio's CTC keyword spotter rescoring the
/// transcript against the audio. Built from the parts of `VocabularyBoostingSession` rather
/// than the session itself, so each proposed rewrite passes `BoostGuard` before it's applied.
///
/// The 0.6B Parakeet models have no CTC head, so this needs the separate Parakeet CTC 110M
/// encoder (about 100 MB, `~/Library/Application Support/FluidAudio/Models/parakeet-ctc-110m-coreml`).
/// Everything here is best-effort by design: until that model is on disk and loaded, or if
/// anything at all goes wrong, `rescore` returns `nil` and the dictation uses the plain
/// transcript. Boosting must never cost the user a dictation, or make one wait for a download.
actor VocabularyBooster {
    /// A transcript boosting changed, and the words it rewrote.
    struct Rescored: Sendable {
        let text: String
        let replacements: [AppliedCorrection]
    }

    private var models: CtcModels?
    private var loading: Task<Void, Never>?
    /// A failed fetch isn't retried on every dictation; offline, that would be a request per
    /// key press.
    private var lastFailure: ContinuousClock.Instant?
    /// Re-tokenizing the terms and rebuilding the rescorer only happens when the list changes.
    private var session: (terms: [String], session: Session)?
    /// The build in progress. Actor methods interleave at every `await`, so without this a
    /// dictation arriving during `prepare(terms:)` would build the same session a second time.
    private var building: (terms: [String], task: Task<Session?, Never>)?

    /// What `VocabularyBoostingSession` holds, kept here so the rescorer's candidates can be
    /// vetted one by one instead of applied wholesale.
    private struct Session: Sendable {
        let vocabulary: CustomVocabularyContext
        let spotter: CtcKeywordSpotter
        let rescorer: VocabularyRescorer
        let sizeConfig: ContextBiasingConstants.VocabSizeConfig
    }
    /// The terms `prepare(terms:)` last asked for, built as soon as the model is loaded.
    private var wantedTerms: [String]?
    /// One CTC pass at a time. Rescoring suspends here while CoreML runs, so a second call
    /// could otherwise start on the same models: a boost that outlived its budget is still
    /// running when the next window of a long recording asks for its own.
    private var ctcBusy = false
    private var ctcWaiters: [CheckedContinuation<Void, Never>] = []

    /// How sure the rescorer must be before it rewrites a word. FluidAudio's defaults are tuned
    /// for keyword-spotting benchmarks, where missing a term costs more than inventing one. In
    /// dictation it's the other way round: a dictionary word written over something the user
    /// actually said is worse than a misspelling, and a mishearing that keeps coming back
    /// belongs in a "when you hear X, write Y" correction, which is exact.
    ///
    /// - No spotter-anchored rescue. That pass rewrites words on acoustic evidence alone, at
    ///   any string similarity. FluidAudio measures it as the main source of false insertions
    ///   (about 94 down to 19 on its short-distractor set when off), at no recall cost on
    ///   distinctive names (FluidAudio #702, #724).
    /// - Short terms get less boost (taper below 5 tokens, exponent 2), so a one-token name can't
    ///   beat a correctly heard common word on the flat boost alone (#702's recommended values).
    static let rescorerConfig = VocabularyRescorer.Config(
        shortTermCbwTaperPivot: 5,
        shortTermCbwTaperExponent: 2.0,
        spotterRescueEnabled: false
    )

    /// The string similarity a heard word needs to its replacement. FluidAudio uses 0.50–0.55
    /// for vocabularies this size; 0.60 is its own setting for large, distractor-heavy lists,
    /// which is what a personal dictionary is in practice: most of its words aren't in any
    /// given dictation.
    static let minimumSimilarity: Float = 0.60

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

    /// The transcript with dictionary terms restored where the audio supports them, and what
    /// was rewritten, or `nil` when boosting can't run yet or changed nothing.
    ///
    /// - Parameter terms: deduplicated, stably ordered, so an unchanged dictionary reuses the
    ///   configured session.
    func rescore(
        text: String,
        tokenTimings: [TokenTiming],
        samples: [Float],
        terms: [String]
    ) async -> Rescored? {
        guard let models else {
            startLoading()
            return nil
        }

        guard let session = await configuredSession(for: terms, models: models) else { return nil }
        // One CTC pass at a time on the shared models: live windows, the key-up tail and a
        // Retry can all ask at once. Waiting counts against the caller's time budget; a caller
        // that gave up while waiting has nothing left to rescore for.
        await acquireCtc()
        defer { releaseCtc() }
        guard !Task.isCancelled else { return nil }
        return await Self.rescore(text: text, tokenTimings: tokenTimings, samples: samples, session: session)
    }

    /// The CTC pass, FluidAudio's candidates, `BoostGuard`, and the rewrite. Static and async,
    /// so it runs off this actor: a boost that overruns its deadline mustn't hold up the next
    /// dictation's call into the actor.
    private static func rescore(
        text: String,
        tokenTimings: [TokenTiming],
        samples: [Float],
        session: Session
    ) async -> Rescored? {
        let evidence: VocabularyRescorer.CandidateEvidenceOutput
        do {
            let spotted = try await session.spotter.spotKeywordsWithLogProbs(
                audioSamples: samples, customVocabulary: session.vocabulary, minScore: nil)
            guard !spotted.logProbs.isEmpty else { return nil }
            // The same call `VocabularyBoostingSession.rescore` makes, minus applying the result.
            evidence = session.rescorer.ctcTokenEvaluateCandidates(
                transcript: text,
                tokenTimings: tokenTimings,
                logProbs: spotted.logProbs,
                frameDuration: spotted.frameDuration,
                cbw: session.sizeConfig.cbw,
                marginSeconds: 0.5,
                minSimilarity: max(session.sizeConfig.minSimilarity, session.vocabulary.minSimilarity)
            )
        } catch {
            Log.speech.notice("vocabulary boosting failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        var accepted: [VocabularyRescorer.CandidateEvidence] = []
        var vetoed = 0
        for candidate in evidence.candidates where candidate.legacyOutcome == .applied {
            guard candidate.wordRange.lowerBound >= 0,
                  candidate.wordRange.upperBound <= evidence.baseWords.count,
                  !candidate.wordRange.isEmpty
            else { continue }
            let heard = Array(evidence.baseWords[candidate.wordRange])
            if BoostGuard.accepts(heard: heard, term: candidate.canonicalTerm) {
                accepted.append(candidate)
            } else {
                vetoed += 1
            }
        }
        if vetoed > 0 {
            Log.speech.info("vocabulary boosting: \(vetoed, privacy: .public) rewrite(s) vetoed by BoostGuard")
        }
        guard !accepted.isEmpty,
              let rescored = rewrite(evidence, applying: accepted)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !rescored.isEmpty, rescored != text
        else { return nil }

        let replacements = applied(accepted)
        let rewritten = replacements.reduce(0) { $0 + $1.count }
        Log.speech.info("vocabulary boosting rewrote \(rewritten, privacy: .public) word(s)")
        return Rescored(text: rescored, replacements: replacements)
    }

    /// Loads the CTC model and builds the session for `terms`, waiting for both, and says
    /// whether boosting is ready. For the speech smoke test, which mustn't race the
    /// background load; dictations use `prepare(terms:)` and never wait.
    func ready(terms: [String]) async -> Bool {
        if models == nil {
            lastFailure = nil
            startLoading()
            await loading?.value
        }
        guard let models else { return false }
        return await configuredSession(for: terms, models: models) != nil
    }

    private func acquireCtc() async {
        guard ctcBusy else {
            ctcBusy = true
            return
        }
        await withCheckedContinuation { ctcWaiters.append($0) }
    }

    private func releaseCtc() {
        if ctcWaiters.isEmpty {
            ctcBusy = false
        } else {
            // Ownership passes straight to the next caller; `ctcBusy` stays true.
            ctcWaiters.removeFirst().resume()
        }
    }

    /// `evidence.baseText` with each accepted candidate's words replaced by its term.
    ///
    /// Spliced into the original text where FluidAudio aligned every candidate to it, which
    /// keeps the transcript's own punctuation and spacing; otherwise rebuilt from the word
    /// list with single spaces, which is what FluidAudio's own rewrite does.
    private static func rewrite(
        _ evidence: VocabularyRescorer.CandidateEvidenceOutput,
        applying accepted: [VocabularyRescorer.CandidateEvidence]
    ) -> String? {
        // Earliest first; overlaps shouldn't survive FluidAudio's arbitration, but never splice two.
        var chosen: [VocabularyRescorer.CandidateEvidence] = []
        for candidate in accepted.sorted(by: { $0.wordRange.lowerBound < $1.wordRange.lowerBound }) {
            if let last = chosen.last, last.wordRange.overlaps(candidate.wordRange) { continue }
            chosen.append(candidate)
        }

        let bytes = Array(evidence.baseText.utf8)
        let ranges = chosen.compactMap(\.baseTextUTF8Range)
        if ranges.count == chosen.count,
           ranges.allSatisfy({ $0.lowerBound >= 0 && $0.upperBound <= bytes.count }) {
            var output = bytes
            for (candidate, range) in zip(chosen, ranges).reversed() {
                output.replaceSubrange(range, with: Array(written(candidate, in: evidence).utf8))
            }
            return String(decoding: output, as: UTF8.self)
        }

        var words: [String] = []
        var index = 0
        for candidate in chosen {
            words += evidence.baseWords[index..<candidate.wordRange.lowerBound]
            // Keep the sentence punctuation the replaced words ended on.
            let ending = String(evidence.baseWords[candidate.wordRange.upperBound - 1]
                .reversed().prefix(while: { ".,;:!?…".contains($0) }).reversed())
            words.append(written(candidate, in: evidence) + ending)
            index = candidate.wordRange.upperBound
        }
        words += evidence.baseWords[index...]
        return words.joined(separator: " ")
    }

    /// The term as it goes into the text: capitalized where the heard words started a sentence
    /// ("kubectl" for "Cube control" at the start), otherwise exactly as the dictionary spells it.
    /// FluidAudio's own rewrite does the same.
    private static func written(
        _ candidate: VocabularyRescorer.CandidateEvidence,
        in evidence: VocabularyRescorer.CandidateEvidenceOutput
    ) -> String {
        let term = candidate.canonicalTerm
        guard let first = term.first, first.isLowercase,
              evidence.baseWords[candidate.wordRange.lowerBound].first?.isUppercase == true
        else { return term }
        return first.uppercased() + term.dropFirst()
    }

    /// The rewrites that were applied, one entry per distinct rewrite, in the order first seen.
    private static func applied(_ candidates: [VocabularyRescorer.CandidateEvidence]) -> [AppliedCorrection] {
        var order: [String] = []
        var found: [String: (from: String, to: String, count: Int)] = [:]
        for candidate in candidates where candidate.basePhrase != candidate.canonicalTerm {
            let key = candidate.basePhrase.lowercased() + "\u{1F}" + candidate.canonicalTerm
            if let seen = found[key] {
                found[key] = (seen.from, seen.to, seen.count + 1)
            } else {
                found[key] = (candidate.basePhrase, candidate.canonicalTerm, 1)
                order.append(key)
            }
        }
        return order.compactMap { found[$0] }.map { AppliedCorrection(from: $0.from, to: $0.to, count: $0.count) }
    }

    /// The configured session for `terms`: cached, joined if already being built, or built now.
    private func configuredSession(for terms: [String], models: CtcModels) async -> Session? {
        if let cached = self.session, cached.terms == terms { return cached.session }
        if let building, building.terms == terms { return await building.task.value }

        let task = Task<Session?, Never> {
            do {
                return try await Self.makeSession(terms: terms, models: models)
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

    /// What `VocabularyBoostingSession.init` does: tokenize the terms with the CTC tokenizer
    /// (terms without CTC token ids are silently skipped by the spotter and rescorer), then
    /// build the spotter and rescorer.
    private static func makeSession(terms: [String], models: CtcModels) async throws -> Session {
        let directory = CtcModels.defaultCacheDirectory(for: models.variant)
        let tokenizer = try await CtcTokenizer.load(from: directory)
        let tokenized = terms.compactMap { text -> CustomVocabularyTerm? in
            let ids = tokenizer.encode(text)
            return ids.isEmpty ? nil : CustomVocabularyTerm(text: text, ctcTokenIds: ids)
        }
        let vocabulary = CustomVocabularyContext(terms: tokenized, minSimilarity: minimumSimilarity)
        let spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter, vocabulary: vocabulary, config: rescorerConfig, ctcModelDirectory: directory)
        return Session(
            vocabulary: vocabulary,
            spotter: spotter,
            rescorer: rescorer,
            sizeConfig: ContextBiasingConstants.rescorerConfig(forVocabSize: vocabulary.terms.count)
        )
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
