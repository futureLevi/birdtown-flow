import MurmurKit
import SwiftUI

// Owned by the lab agent: Lab states beyond the ones in `SnapshotCatalog+Main`.
extension SnapshotCatalog {
    static var labResults: [SnapshotRenderer.Shot] {
        let size = CGSize(width: 1040, height: 2_700)
        let records = SampleData.records()
        let sample = MainPreview(status: SampleData.readyStatus, firstName: "Levi")
        return [
            // Results from two tests: the current text's Run All batch under one header, and an
            // earlier email under its own, marked earlier and offering to use its text again.
            SnapshotRenderer.Shot("lab-results-grouped", size: size) {
                labGrouped(records: records, preview: sample)
            },
        ]
    }

    private static func labGrouped(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = AppModel.preview(records: records, lab: SampleData.labState)
        model.section = .lab
        model.settings.polishProvider = .claudeCode
        model.bench.preview(
            selected: SampleData.labDraft.id, draft: SampleData.labDraft,
            runs: SampleData.labRuns() + earlierRuns)
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    /// Two configurations tried on an email dictated before the current test text.
    private static var earlierRuns: [LabBench.Run] {
        let configs = SampleData.labConfigurations
        let input = "hi dana um just checking in on the the quarterly numbers could you send them over by end of day "
            + "thanks"
        let polished = "Hi Dana,\n\nJust checking in on the quarterly numbers. Could you send them over by end of day?\n\nThanks"
        func run(_ config: PolishConfiguration, minutesAgo: Double, milliseconds: Int) -> LabBench.Run {
            LabBench.Run(
                configuration: config, wasEdited: false, input: input, style: .formal, category: .email,
                appName: "Mail", ranAt: Date().addingTimeInterval(-minutesAgo * 60),
                result: .init(verdict: .accepted(polished), totalMilliseconds: milliseconds),
                output: polished)
        }
        return [
            run(configs[1], minutesAgo: 32, milliseconds: 1_388),
            run(configs[0], minutesAgo: 33, milliseconds: 912),
        ]
    }
}
