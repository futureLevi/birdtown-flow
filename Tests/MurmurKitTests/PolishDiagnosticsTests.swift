import Foundation
import Testing
@testable import MurmurKit

@Suite("PolishDiagnostics")
struct PolishDiagnosticsTests {
    private let cold = PolishDiagnostics(
        model: "fast-model-1", effort: "low", startedCold: true, coldReason: "differentSetup",
        modelMs: 1_180, sessionMs: 1_402)

    @Test("Every measured field goes on the summary line, in a fixed order")
    func summaryFields() {
        var line = TimingLine("dictation")
        line.ms("polish", 3_612)
        var diagnostics = cold
        diagnostics.spareAgeMs = 0
        diagnostics.addFields(to: &line)
        #expect(line.text == "dictation polish=3612ms polishCold=1 polishColdReason=differentSetup "
            + "polishModel=1180ms polishSession=1402ms polishSpareAge=0ms "
            + "polishModelName=fast-model-1 polishEffort=low")
    }

    @Test("A warm request says so; what wasn't measured is left out")
    func warmAndUnmeasured() {
        var line = TimingLine("x")
        PolishDiagnostics(model: "fast-model-1", startedCold: false, spareAgeMs: 41_250).addFields(to: &line)
        #expect(line.text == "x polishCold=0 polishSpareAge=41250ms polishModelName=fast-model-1")

        var empty = TimingLine("x")
        PolishDiagnostics().addFields(to: &empty)
        #expect(empty.text == "x")
    }

    @Test("A model name with spaces or other characters stays one token")
    func modelToken() {
        #expect(PolishDiagnostics.token("local-model3.2:3b") == "local-model3.2:3b")
        #expect(PolishDiagnostics.token("vendor/fast-model@2026") == "vendor/fast-model@2026")
        #expect(PolishDiagnostics.token(" my model (v2) ") == "my_model__v2_")
        #expect(PolishDiagnostics.token("modèle") == "mod_le")
        #expect(PolishDiagnostics.token("  ") == "_")
    }

    @Test("Parts: the slowest times key-up waited for, cold if any part was")
    func parts() {
        let warm = PolishDiagnostics(startedCold: false, modelMs: 900, sessionMs: 1_000, spareAgeMs: 5_000)
        let combined = PolishDiagnostics.parts([warm, cold, warm], model: "fast-model-1", effort: "low")
        #expect(combined == PolishDiagnostics(
            model: "fast-model-1", effort: "low", startedCold: true, coldReason: "differentSetup",
            modelMs: 1_180, sessionMs: 1_402, coldParts: 1))
    }

    @Test("Parts that all started warm: not cold, none counted")
    func warmParts() {
        let warm = PolishDiagnostics(startedCold: false, modelMs: 900)
        let combined = PolishDiagnostics.parts([warm, warm], model: "m", effort: nil)
        #expect(combined.startedCold == false)
        #expect(combined.coldParts == 0)
        #expect(combined.coldReason == nil)
        #expect(combined.modelMs == 900)
    }

    @Test("Parts from a provider that reports no timings carry only the model")
    func unmeasuredParts() {
        let combined = PolishDiagnostics.parts([PolishDiagnostics(), PolishDiagnostics()], model: "small-model-4.1", effort: nil)
        #expect(combined == PolishDiagnostics(model: "small-model-4.1"))
        // Every part polished while the person talked: key-up waited for none.
        #expect(PolishDiagnostics.parts([], model: "m", effort: "low") == PolishDiagnostics(model: "m", effort: "low"))
    }

    @Test("History takes the model's time, the cold start, the model and its effort")
    func setPolish() {
        var timings = DictationTimings(transcribeMs: 300, polishMs: 3_612, totalMs: 4_000)
        timings.setPolish(cold)
        #expect(timings.polishModelMs == 1_180)
        #expect(timings.polishStartedCold == true)
        #expect(timings.polishModel == "fast-model-1")
        #expect(timings.polishEffort == "low")

        // A Retry that didn't polish clears them.
        timings.setPolish(nil)
        #expect(timings == DictationTimings(transcribeMs: 300, polishMs: 3_612, totalMs: 4_000))
    }

    @Test("History's polish detail reads cold start, model time, then model and effort")
    func polishDetails() {
        var timings = DictationTimings(polishMs: 3_612, totalMs: 4_000)
        timings.setPolish(cold)
        let format: (Int) -> String = { "\($0) ms" }
        #expect(timings.polishDetails(format: format) == ["cold start", "model 1180 ms", "fast-model-1 low"])

        timings.polishStartedCold = false
        timings.polishEffort = nil
        #expect(timings.polishDetails(format: format) == ["model 1180 ms", "fast-model-1"])

        #expect(DictationTimings(polishMs: 800, totalMs: 900).polishDetails(format: format).isEmpty)
    }
}
