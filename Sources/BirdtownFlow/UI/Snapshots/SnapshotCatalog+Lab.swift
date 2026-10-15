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
            // A retry that failed: the text and the earlier result stay, the error sits beside
            // Retry, and the editor says it's saved.
            SnapshotRenderer.Shot("lab-test-failed", size: CGSize(width: 1040, height: 1_500)) {
                labFailed(records: records, preview: sample)
            },
        ]
    }

    private static func labFailed(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = AppModel.preview(records: records, lab: SampleData.labState)
        model.section = .lab
        model.settings.polishProvider = .claudeCode
        let config = SampleData.labConfigurations[0]
        let polished = "So I was thinking we could move the Birdtown review to Friday, no wait, Thursday, and then "
            + "send the deck to Sarah before then. Does that work for you?"
        func run(minutesAgo: Double, result: PolishService.LabResult, output: String) -> LabBench.Run {
            LabBench.Run(
                configuration: config, wasEdited: false, input: LabBench.defaultSample, style: .casual,
                category: .work, appName: "Slack", ranAt: Date().addingTimeInterval(-minutesAgo * 60),
                result: result, output: output)
        }
        model.bench.preview(
            selected: config.id, draft: nil,
            runs: [
                run(minutesAgo: 0,
                    result: .init(verdict: .failed("Claude Code didn't answer within 10 s. Check that it is signed in, then retry."),
                                  totalMilliseconds: 0),
                    output: ""),
                run(minutesAgo: 3,
                    result: .init(verdict: .accepted(polished), totalMilliseconds: 1_046, modelMilliseconds: 842,
                                  sessionMilliseconds: 1_003),
                    output: polished),
            ])
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
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
