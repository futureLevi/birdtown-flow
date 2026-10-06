import Foundation
import MurmurDictionary

// CONTRACT — owned by the MurmurKit agent. Signatures here are what the app calls; the
// bodies are placeholders until the real implementation lands.
//
// Order of operations for one dictation:
//
//   raw engine text
//     → TextPipeline.prepare        fillers, stutters, spoken commands ("new line")
//     → [optional AI polish]        app-side, see PolishService
//     → TextPipeline.finalize       dictionary corrections, snippets, style rules
//     → inserted
//
// `finalize` runs even when polish succeeded, so the dictionary's guarantees hold no matter
// what the model wrote.

public struct PipelineOptions: Sendable {
    public var removeFillers: Bool
    public var spokenCommands: Bool

    public init(removeFillers: Bool = true, spokenCommands: Bool = true) {
        self.removeFillers = removeFillers
        self.spokenCommands = spokenCommands
    }
}

public struct PipelineResult: Sendable, Equatable {
    public var text: String
    public var corrections: [AppliedCorrection]
    /// Triggers of the snippets that expanded.
    public var snippets: [String]

    public init(text: String, corrections: [AppliedCorrection] = [], snippets: [String] = []) {
        self.text = text
        self.corrections = corrections
        self.snippets = snippets
    }
}

public enum TextPipeline {
    /// Deterministic cleanup before any AI polish.
    public static func prepare(_ raw: String, options: PipelineOptions = PipelineOptions()) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dictionary, snippets, then the writing style's casing/punctuation rules.
    public static func finalize(
        _ text: String,
        style: WritingStyle,
        corrector: DictionaryCorrector,
        snippets: [Snippet]
    ) -> PipelineResult {
        let (corrected, applied) = corrector.apply(to: text)
        return PipelineResult(text: corrected, corrections: applied, snippets: [])
    }
}

/// Maps the frontmost app to an `AppCategory`.
public enum AppCategoryResolver {
    public static func category(bundleID: String?, windowTitle: String?) -> AppCategory {
        .other
    }
}
