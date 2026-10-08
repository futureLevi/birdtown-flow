import Foundation
import MurmurKit
import Observation

/// The Lab's working state: which setup is open, edits not saved yet, the test text and the
/// results so far. It lives as long as the app, so leaving the page loses nothing; quitting
/// does lose unsaved edits and results, which the page says.
@MainActor
@Observable
final class LabBench {
    /// One configuration run on one piece of text.
    struct Run: Identifiable {
        let id = UUID()
        /// The version that ran, so the result still makes sense after more edits.
        let configuration: PolishConfiguration
        /// It ran with changes that weren't saved.
        let wasEdited: Bool
        let input: String
        let style: WritingStyle
        let category: AppCategory
        let appName: String?
        let ranAt: Date
        /// `nil` while it runs.
        var result: PolishService.LabResult?
        /// What dictation would type: the reply (or the transcript, if the reply was refused)
        /// after the style and the dictionary.
        var output = ""
        /// It failed for something only Settings can fix, such as a missing API key, so the
        /// result can link there.
        var needsSettings = false
    }

    /// Newest first.
    var runs: [Run] = []
    var selectedID: UUID?
    var sample = LabBench.defaultSample
    var sampleStyle: WritingStyle = .casual
    var sampleCategory: AppCategory = .work
    var sampleAppName: String? = "Slack"
    /// The run in progress, while one is.
    private(set) var runningID: UUID?

    private var drafts: [UUID: PolishConfiguration] = [:]
    private var task: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?

    private let settings: Settings
    private let lab: PolishLabStore
    private let dictionary: DictionaryStore
    private let snippets: SnippetStore

    static let maxRuns = 40

    /// Fillers, a stutter, a self-correction, a question and two names from the dictionary:
    /// enough for a setup to show what it does.
    static let defaultSample =
        "um so I was like thinking we we could move the bird town review to Friday no wait Thursday and then you know send the deck to Sarah before then. does that work for you"

    init(settings: Settings, lab: PolishLabStore, dictionary: DictionaryStore, snippets: SnippetStore) {
        self.settings = settings
        self.lab = lab
        self.dictionary = dictionary
        self.snippets = snippets
        selectedID = lab.configurations.first?.id
    }

    // MARK: - Editing

    /// The version on screen: unsaved edits if there are any, otherwise what's saved.
    func version(of id: UUID) -> PolishConfiguration? {
        drafts[id] ?? lab.configuration(id: id)
    }

    var selected: PolishConfiguration? { selectedID.flatMap(version(of:)) }

    func hasUnsavedChanges(_ id: UUID) -> Bool { drafts[id] != nil }

    /// Keeps an edit without saving it. Editing back to what's saved clears the draft.
    func edit(_ configuration: PolishConfiguration) {
        guard let saved = lab.configuration(id: configuration.id) else { return }
        drafts[configuration.id] = configuration.hasSameSetup(as: saved) ? nil : configuration
        schedulePrewarm()
    }

    func save(_ id: UUID) {
        guard let draft = drafts[id] else { return }
        lab.update(draft)
        drafts[id] = nil
    }

    func revert(_ id: UUID) {
        drafts[id] = nil
        schedulePrewarm()
    }

    /// The edits become a new configuration, and the original goes back to what was saved.
    func saveAsCopy(_ id: UUID) {
        guard let current = version(of: id) else { return }
        let copy = lab.duplicate(current)
        drafts[id] = nil
        selectedID = copy.id
    }

    /// A copy of what's saved.
    func duplicate(_ id: UUID) {
        guard let saved = lab.configuration(id: id) else { return }
        selectedID = lab.duplicate(saved).id
    }

    func addNew() {
        selectedID = lab.addUntitled().id
    }

    func delete(_ id: UUID) {
        let ids = lab.configurations.map(\.id)
        let index = ids.firstIndex(of: id) ?? 0
        lab.delete(id: id)
        drafts[id] = nil
        if selectedID == id {
            let remaining = lab.configurations
            selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }

    // MARK: - Test text

    /// Recent dictations with something said, newest first, to test with. History is kept
    /// newest first, so this stops after `limit` matches instead of scanning everything.
    func recentDictations(from history: HistoryStore, limit: Int = 8) -> [HistoryRecord] {
        Array(
            history.records.lazy
                .filter { !$0.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(limit)
        )
    }

    /// Tests with exactly what the speech engine heard, in the app and style it went to.
    func useDictation(_ record: HistoryRecord) {
        sample = record.rawText
        if let category = record.context?.category { sampleCategory = category }
        sampleAppName = record.context?.appName
        sampleStyle = record.style ?? settings.style(for: sampleCategory)
        schedulePrewarm()
    }

    // MARK: - Running

    var isRunning: Bool { task != nil }

    var canRun: Bool {
        !isRunning && !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run(_ id: UUID) {
        guard canRun, let configuration = version(of: id) else { return }
        start([(configuration, hasUnsavedChanges(id))])
    }

    /// Every configuration, as it is on screen, one after another on the same text.
    func runAll() {
        guard canRun else { return }
        start(lab.configurations.compactMap { saved in
            version(of: saved.id).map { ($0, hasUnsavedChanges(saved.id)) }
        })
    }

    func cancel() {
        task?.cancel()
    }

    func clearResults() {
        guard !isRunning else { return }
        runs = []
    }

    private func start(_ queue: [(PolishConfiguration, Bool)]) {
        guard !queue.isEmpty else { return }
        prewarmTask?.cancel()
        let input = sample
        let style = sampleStyle
        let category = sampleCategory
        let appName = sampleAppName
        task = Task { [weak self] in
            for (configuration, edited) in queue {
                guard let self, !Task.isCancelled else { break }
                await self.perform(configuration, edited: edited, input: input, style: style,
                                   category: category, appName: appName)
            }
            self?.task = nil
            self?.runningID = nil
        }
    }

    /// Exactly what dictation does after transcription (Birdtown Flow's own cleanup, polish,
    /// then the style and the dictionary), except that nothing falls back quietly.
    private func perform(
        _ configuration: PolishConfiguration, edited: Bool, input: String, style: WritingStyle,
        category: AppCategory, appName: String?
    ) async {
        let run = Run(
            configuration: configuration, wasEdited: edited, input: input, style: style, category: category,
            appName: appName, ranAt: Date())
        runs.insert(run, at: 0)
        if runs.count > Self.maxRuns { runs.removeLast(runs.count - Self.maxRuns) }
        runningID = run.id

        let options = PipelineOptions(removeFillers: settings.removeFillers, spokenCommands: settings.spokenCommands)
        let prepared = TextPipeline.prepare(input, options: options)
        let vocabulary = dictionary.biasPhrases
        let request = PolishRequest(
            text: prepared, style: style, category: category, appName: appName, vocabulary: vocabulary,
            level: settings.polishLevel)
        let result = await PolishService(settings: settings).labRun(configuration, request: request)

        let polished: String
        if case .accepted(let text) = result.verdict { polished = text } else { polished = prepared }
        let output = TextPipeline.finalize(
            polished, style: style, corrector: dictionary.corrector, snippets: snippets.enabled,
            vocabulary: vocabulary
        ).text
        var needsSettings = false
        if case .failed = result.verdict {
            // The same check `PolishService` makes before it calls the API.
            needsSettings = configuration.provider == .anthropic && Keychain.string(for: .anthropic) == nil
        }
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index].result = result
            runs[index].output = output
            runs[index].needsSettings = needsSettings
        }
    }

    // MARK: - Claude Code

    /// Starts a Claude Code session for the open configuration and the test text's style, so
    /// the next run's time is what a dictation would wait (dictation starts its session while
    /// you talk). Waits for a pause so typing in the editor doesn't start one per keystroke.
    func schedulePrewarm() {
        prewarmTask?.cancel()
        guard !isRunning, let configuration = selected, configuration.provider == .claudeCode else { return }
        let request = PolishRequest(
            text: "", style: sampleStyle, category: sampleCategory, appName: sampleAppName,
            vocabulary: dictionary.biasPhrases, level: settings.polishLevel, instructions: configuration.instructions)
        prewarmTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            PolishService.claudeCode(model: configuration.model, effort: configuration.effort).prewarm(request)
        }
    }

    // MARK: - Snapshots

    /// Puts edits and results in place for snapshots, without running anything.
    func preview(selected: UUID?, draft: PolishConfiguration?, runs: [Run]) {
        selectedID = selected
        if let draft { drafts[draft.id] = draft }
        self.runs = runs
    }
}
