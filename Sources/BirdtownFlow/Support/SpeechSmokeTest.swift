import Foundation
import MurmurDictionary
import MurmurKit

/// `BirdtownFlow --transcribe <file.wav> [engine]`: loads the speech model (downloading it if
/// needed), transcribes the file, runs the text pipeline, and prints what happened.
///
/// CI feeds it speech synthesized with `say`, which proves the part no compiler can: that
/// the model downloads, compiles, and turns real audio into the right words. Uses its own
/// defaults domain so it never touches the user's settings.
///
/// With `--compare-segmented` it checks long recordings instead (`compareSegmented`).
@MainActor
enum SpeechSmokeTest {
    static func run(file: URL, engine engineName: String?) async -> Int32 {
        let defaults = UserDefaults(suiteName: "Murmur.SmokeTest") ?? .standard
        let settings = Settings(defaults: defaults)
        if let engineName, let choice = SpeechEngineChoice(rawValue: engineName) {
            settings.engine = choice
        }
        let models = ModelManager(settings: settings)
        let clock = ContinuousClock()

        print("[smoke] preparing \(settings.engine.displayName)")
        let prepareStart = clock.now
        await models.prepare()
        print("[smoke] model state \(models.state) after \(prepareStart.duration(to: clock.now))")
        guard case .ready = models.state else {
            print("[smoke] FAIL: the model did not become ready")
            return 2
        }

        do {
            let samples = try AudioRecorder.readSamples(from: file)
            print("[smoke] \(samples.count) samples, \(String(format: "%.2f", Double(samples.count) / 16_000)) s")
            let engine = try await models.engine()
            let arguments = CommandLine.arguments
            if arguments.contains("--compare-segmented") {
                return try await compareSegmented(samples, engine: engine, models: models, arguments: arguments)
            }
            let vocabulary = ["Birdtown Flow", "Parakeet"]

            // Twice: the first call includes any lazy warm-up, the second is what a user feels.
            for attempt in 1...2 {
                let start = clock.now
                let raw = try await engine.transcribe(samples, vocabulary: vocabulary)
                let elapsed = start.duration(to: clock.now)
                let prepared = TextPipeline.prepare(raw)
                let result = TextPipeline.finalize(
                    prepared,
                    style: .formal,
                    corrector: DictionaryCorrector(entries: []),
                    snippets: [],
                    vocabulary: vocabulary
                )
                print("[smoke] pass \(attempt) · \(engine.displayName) · \(elapsed)")
                print("[smoke] raw:   \(raw)")
                print("[smoke] final: \(result.text)")
                if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("[smoke] FAIL: empty transcript")
                    return 3
                }
            }
            return 0
        } catch {
            print("[smoke] FAIL: \(error.localizedDescription)")
            return 4
        }
    }

    // MARK: - Long recordings

    /// `--compare-segmented`: transcribes the file whole, then window by window as a long
    /// Retry does (`SegmentedTranscriber.offline`), prints both and checks they agree: at most
    /// 1.0% of words changed, no words doubled at a seam. Speed is checked against the whole
    /// pass on the same machine, since CI's virtual Mac is much slower than a real one: the
    /// windows together take at most 1.75× the whole pass (their overlap alone adds about a
    /// quarter), and no window more than twice the whole pass's time for 15 s of audio. Each
    /// `--term <phrase>` is boosted (the CTC model must load) and must come out of both, and
    /// what boosting rewrote in each is printed; `--expect-forced` asks for at least one cut
    /// made without a pause. Any failed check exits non-zero.
    private static func compareSegmented(
        _ samples: [Float], engine: any TranscriptionEngine, models: ModelManager, arguments: [String]
    ) async throws -> Int32 {
        guard let windowed = engine as? any WindowedTranscriptionEngine else {
            print("[segmented] FAIL: \(engine.displayName) doesn't transcribe in windows")
            return 5
        }
        let terms = arguments.indices.dropLast().compactMap { arguments[$0] == "--term" ? arguments[$0 + 1] : nil }
        var boostingReady = true
        if !terms.isEmpty {
            boostingReady = await models.prepareBoosting(for: terms)
            print("[segmented] boosting \(terms.joined(separator: ", ")): \(boostingReady ? "ready" : "NOT ready")")
        }
        let clock = ContinuousClock()

        let wholeStart = clock.now
        let whole = try await engine.transcript(samples, vocabulary: terms)
        let wholeTime = wholeStart.duration(to: clock.now)

        let windowsStart = clock.now
        let segmented: SegmentedTranscriber.Outcome
        do {
            segmented = try await SegmentedTranscriber.offline(samples, engine: windowed, vocabulary: terms)
        } catch let unavailable as SegmentedTranscriber.Unavailable {
            print("[segmented] FAIL: the windows were given up (\(unavailable.reason))")
            return 5
        }
        let windowsTime = windowsStart.duration(to: clock.now)

        print("[segmented] whole · \(wholeTime): \(whole.text)")
        print("[segmented] windows · \(windowsTime): \(segmented.transcript.text)")
        print("[segmented] \(segmented.line.text)")
        for (index, part) in segmented.parts.enumerated() {
            print("[segmented] part \(index + 1): \(part)")
        }
        // Whether a term came from boosting or the model heard it unaided.
        print("[segmented] boosted whole:   \(Self.rewrites(whole.boosted))")
        print("[segmented] boosted windows: \(Self.rewrites(segmented.transcript.boosted))")

        let (removed, added) = WordDiff.counts(original: whole.text, revised: segmented.transcript.text)
        let words = whole.text.split(whereSeparator: \.isWhitespace).count
        // A word swapped for another is one removed and one added: one change.
        let changed = Double(max(removed, added)) / Double(max(words, 1))
        for segment in WordDiff.diff(original: whole.text, revised: segmented.transcript.text) {
            switch segment {
            case .removed(let text): print("[segmented] only whole:   \(text)")
            case .added(let text): print("[segmented] only windows: \(text)")
            case .same: break
            }
        }
        let doubled = SegmentStitcher.doubledSeams(segmented.parts, reference: whole.text)

        var failed = false
        func check(_ name: String, _ passed: Bool, _ detail: String) {
            print("[segmented] \(passed ? "ok" : "FAIL"): \(name) (\(detail))")
            if !passed { failed = true }
        }
        check("words changed ≤ 1.0%", changed <= 0.01,
              "\(String(format: "%.2f", changed * 100))%, -\(removed) +\(added) of \(words)")
        check("no word doubled at a seam", doubled.isEmpty, doubled.isEmpty ? "none" : doubled.joined(separator: ", "))
        let cost = Self.seconds(windowsTime) / max(Self.seconds(wholeTime), 0.001)
        check("windows ≤ 1.75× the whole pass", cost <= 1.75, String(format: "%.2f×", cost))
        // A window holds at most 15 s of audio: twice the whole pass's pace for that much.
        let pace = Self.seconds(wholeTime) / max(Double(samples.count) / 16_000, 1)
        let slowestLimit = Int((2 * 15 * pace * 1000).rounded())
        check("slowest window ≤ 2× the whole pass's pace", segmented.slowestWindowMs <= slowestLimit,
              "\(segmented.slowestWindowMs) ms of \(slowestLimit) ms, \(segmented.windows) windows")
        if arguments.contains("--expect-forced") {
            check("a cut without a pause", segmented.forcedCuts >= 1, "\(segmented.forcedCuts) forced")
        }
        // Without the CTC model both passes run unboosted, and a term the model hears unaided
        // would still pass the check below.
        if !terms.isEmpty {
            check("boosting ready", boostingReady, boostingReady ? "CTC model and terms loaded" : "not loaded")
        }
        for term in terms {
            let inWhole = whole.text.localizedCaseInsensitiveContains(term)
            let inWindows = segmented.transcript.text.localizedCaseInsensitiveContains(term)
            check("\"\(term)\" in both", inWhole && inWindows, "whole \(inWhole), windows \(inWindows)")
        }
        return failed ? 5 : 0
    }

    /// `"Bird town" → "Birdtown" ×1, …`, or `none`.
    private static func rewrites(_ corrections: [AppliedCorrection]) -> String {
        guard !corrections.isEmpty else { return "none" }
        return corrections.map { "\"\($0.from)\" → \"\($0.to)\" ×\($0.count)" }.joined(separator: ", ")
    }

    private static func seconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
