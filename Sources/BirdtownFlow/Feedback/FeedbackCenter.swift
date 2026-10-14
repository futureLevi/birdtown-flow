import Foundation
import MurmurKit
import Observation

/// Product feedback said with the feedback shortcut: the note is saved in the outbox, then
/// filed as a GitHub issue in a private repository (`Settings.feedbackRepository`) with a token
/// from the Keychain. A routine in the developer's project picks new issues up from there.
///
/// Nothing is lost on the way: a note that can't be filed (no token yet, offline) waits in the
/// outbox and goes with the next note, at the next launch, or from Settings' Send Now.
@MainActor
@Observable
final class FeedbackCenter {
    let outbox: FeedbackOutbox
    let settings: Settings
    /// Notes being filed right now, so a note is never sent twice at once.
    private(set) var inFlight: Set<UUID> = []

    @ObservationIgnored private var retryTask: Task<Void, Never>?

    /// Waits this long after a failure that needs no one to fix it (offline, GitHub busy).
    static let retryDelay: Duration = .seconds(10 * 60)

    init(settings: Settings, outbox: FeedbackOutbox) {
        self.settings = settings
        self.outbox = outbox
    }

    var repository: GitHubRepository? { GitHubRepository(settings.feedbackRepository) }
    var hasToken: Bool { Keychain.hasValue(for: .githubFeedback) }
    var isSetUp: Bool { repository != nil && hasToken }

    /// What happened to a note, as the HUD says it.
    enum Delivery: Equatable {
        case sent(issueNumber: Int)
        /// Saved; it goes once Settings has a token and a repository.
        case needsSetup
        /// Saved; it goes when GitHub can be reached.
        case willRetry
        /// Saved; GitHub refused it for a reason someone has to fix in Settings.
        case refused(String)

        var message: String {
            switch self {
            case .sent: "Feedback sent"
            case .needsSetup: "Feedback saved · set up sending in Settings"
            case .willRetry: "Feedback saved · it will send when GitHub can be reached"
            case .refused(let reason): "Feedback saved, not sent · \(reason)"
            }
        }
    }

    /// The note for a recording, with what makes it actionable. The words come later.
    func makeNote(id: UUID, createdAt: Date, context: AppContext?, audioFileName: String?,
                  audioDuration: Double, recentDictations: [HistoryRecord]) -> FeedbackNote {
        FeedbackNote(
            id: id,
            createdAt: createdAt,
            text: "",
            rawText: "",
            audioFileName: audioFileName,
            audioDuration: audioDuration,
            appVersion: AppVersion.display,
            commit: AppVersion.commit,
            system: "macOS " + ProcessInfo.processInfo.operatingSystemVersionString,
            frontmostApp: context?.appName,
            frontmostBundleID: context?.bundleID,
            setup: setupDetails(),
            recentDictations: settings.feedbackIncludesDictations
                ? FeedbackNote.recentDictations(from: recentDictations, now: createdAt)
                : []
        )
    }

    /// Saves `note` and files it. Returns once GitHub has answered or the attempt failed; the
    /// note is in the outbox either way.
    func submit(_ note: FeedbackNote) async -> Delivery {
        outbox.save(note)
        let delivery = await send(id: note.id)
        // Notes that waited (no token then, offline) go with this one.
        if case .sent = delivery { Task { await sendPending() } }
        return delivery
    }

    /// Files every note still waiting, oldest first. Stops at the first failure that would
    /// fail the rest too.
    func sendPending() async {
        for note in outbox.pending where !inFlight.contains(note.id) {
            switch await send(id: note.id) {
            case .sent: continue
            default: return
            }
        }
    }

    /// Esc while the note was being said or transcribed: nothing of it stays.
    func discard(id: UUID) {
        outbox.delete(id: id)
    }

    private func send(id: UUID) async -> Delivery {
        guard var note = outbox.note(id: id), !note.delivery.isSent, note.hasWords else {
            return .refused("nothing to send")
        }
        guard let repository else { return .needsSetup }
        guard let token = Keychain.string(for: .githubFeedback) else { return .needsSetup }
        guard !inFlight.contains(id) else { return .willRetry }
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        note.delivery.attempts += 1
        note.delivery.lastAttempt = Date()
        let client = GitHubIssueClient(repository: repository, token: token)
        do {
            let created = try await client.file(note)
            note.delivery.issueNumber = created.number
            note.delivery.issueURL = created.url
            note.delivery.lastError = nil
            outbox.save(note)
            Log.feedback.notice("filed feedback as \(repository.description, privacy: .public)#\(created.number)")
            return .sent(issueNumber: created.number)
        } catch {
            let failure = error as? FeedbackSendError ?? .offline(error.localizedDescription)
            note.delivery.lastError = failure.message
            outbox.save(note)
            Log.feedback.error("feedback not filed: \(failure.message, privacy: .public)")
            if failure.isTransient {
                scheduleRetry()
                return .willRetry
            }
            return .refused(failure.message)
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            await self.sendPending()
        }
    }

    /// How dictation is set up, for the note: what a bug usually depends on.
    private func setupDetails() -> [FeedbackNote.Detail] {
        var details = [FeedbackNote.Detail("Engine", settings.engine.displayName)]
        details.append(.init("Vocabulary boosting", settings.vocabularyBoosting ? "on" : "off"))
        var polish = settings.polishProvider.title
        switch settings.polishProvider {
        case .anthropic: polish += " (\(settings.anthropicModel))"
        case .openAICompatible: polish += " (\(settings.openAIModel))"
        default: break
        }
        if settings.polishProvider != .off { polish += ", \(settings.polishLevel.rawValue)" }
        details.append(.init("Polish", polish))
        details.append(.init("Live transcription", settings.liveTranscription ? "on" : "off"))
        return details
    }
}
