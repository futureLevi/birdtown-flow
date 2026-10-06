import Foundation
import MurmurDictionary
import MurmurKit

/// `BirdtownFlow --transcribe <file.wav> [engine]`: loads the speech model (downloading it if
/// needed), transcribes the file, runs the text pipeline, and prints what happened.
///
/// CI feeds it speech synthesized with `say`, which proves the part no compiler can: that
/// the model downloads, compiles, and turns real audio into the right words. Uses its own
/// defaults domain so it never touches the user's settings.
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
}
