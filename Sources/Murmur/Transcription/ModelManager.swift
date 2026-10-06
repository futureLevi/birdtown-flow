import FluidAudio
import Foundation
import Network
import Observation

/// Owns the speech model: download, load, warm-up, and vending the engine.
///
/// Parakeet models live where FluidAudio keeps them,
/// `~/Library/Application Support/FluidAudio/Models/<repo>/` (`parakeet-ultra-coreml`,
/// `parakeet-tdt-0.6b-v3-coreml`, `parakeet-tdt-0.6b-v2-coreml`). Downloads resume: FluidAudio
/// streams into `.partial` files with HTTP range requests and keeps them on network failure,
/// so calling `prepare()` again after a failure picks up where the last attempt stopped.
@MainActor
@Observable
final class ModelManager {
    enum State: Equatable {
        case notDownloaded
        /// `progress` is 0…1 when known.
        case downloading(progress: Double?)
        case loading
        case ready
        case failed(String)
    }

    /// Describes the engine selected in Settings, and converges on `.ready` for it.
    private(set) var state: State = .notDownloaded

    private let settings: Settings

    private struct Loaded {
        let choice: SpeechEngineChoice
        let engine: any TranscriptionEngine
    }

    private struct Inflight {
        let id: Int
        let choice: SpeechEngineChoice
        let task: Task<Void, Never>
    }

    /// The engine serving dictations. A previous engine stays here until its replacement is
    /// warmed up, so switching never leaves a window where a dictation has nothing to run on.
    /// Dropping the reference releases the model once any transcription still using it ends.
    @ObservationIgnored private var loaded: Loaded?
    @ObservationIgnored private var inflight: Inflight?
    /// Loads cancelled by an engine switch, by choice. Cancellation is cooperative, so a
    /// cancelled download can still be writing its `.partial` files for a moment; a new load
    /// of the same model waits for it rather than streaming into the same files alongside it.
    @ObservationIgnored private var windingDown: [SpeechEngineChoice: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var appleFallback: AppleSpeechEngine?
    /// Watches for the network after a download failed for lack of it, to resume on its own.
    @ObservationIgnored private var connectivity: NWPathMonitor?
    @ObservationIgnored private var wentOffline = false
    @ObservationIgnored private var retriedWhileOnline = false
    private let booster = VocabularyBooster()
    /// Snapshot and preview instances show a fixed state and never touch the disk or network.
    private let isPreview: Bool

    /// FluidAudio reports a repo load as download 0–0.5 then CoreML compile 0.5–1
    /// (`ProgressReporter.downloadPhaseWeight`); the bar shows the download half as 0–100 %.
    private static let downloadPhaseWeight = 0.5
    /// How long a dictation waits for a model that's loading from disk before it falls back to
    /// whatever else can transcribe. The first-ever load includes an ANE compile that can run
    /// far longer than anyone should stare at a spinner.
    private static let loadWaitLimit: Duration = .seconds(8)

    init(settings: Settings) {
        self.settings = settings
        self.isPreview = false
        observeEngineSetting()
        // A model already on disk starts loading right away, so `.loading` is never a claim
        // without a load behind it (onboarding can read `state` before the app has started).
        // A missing one waits for `prepare()`: downloading is the user's call.
        if isDownloaded(settings.engine) {
            state = .loading
            Task { await self.prepare() }
        }
    }

    /// A manager frozen in `previewState`, for SwiftUI previews and snapshot rendering.
    init(settings: Settings, previewState: State) {
        self.settings = settings
        self.isPreview = true
        state = previewState
    }

    // MARK: - Disk

    /// Whether the model files for `choice` are already on disk. Apple Speech is managed by
    /// macOS and counts as present.
    func isDownloaded(_ choice: SpeechEngineChoice) -> Bool {
        guard let version = choice.asrVersion else { return true }
        let directory = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: directory, version: version) && !Self.containsPartialDownload(directory)
    }

    /// Bytes `choice` occupies on disk, or `nil` when nothing is there (or it's Apple's).
    func diskSize(of choice: SpeechEngineChoice) -> Int64? {
        guard let version = choice.asrVersion else { return nil }
        return Self.allocatedSize(of: AsrModels.defaultCacheDirectory(for: version))
    }

    /// Whether `deleteModel(choice)` would remove anything. The selected engine can't be
    /// deleted out from under the next dictation; pick another engine first.
    func canDelete(_ choice: SpeechEngineChoice) -> Bool {
        choice.isParakeet && choice != settings.engine && diskSize(of: choice) != nil
    }

    /// Removes downloaded files for `choice` to reclaim disk space.
    ///
    /// Refused for the engine selected in Settings (see `canDelete`). A model kept loaded from
    /// before a switch is unloaded first.
    func deleteModel(_ choice: SpeechEngineChoice) {
        guard !isPreview, let version = choice.asrVersion else { return }
        guard choice != settings.engine else {
            Log.speech.notice("not deleting \(choice.engineName, privacy: .public): it's the selected engine")
            return
        }
        if inflight?.choice == choice { cancelInflight() }
        if loaded?.choice == choice { loaded = nil }

        let directory = AsrModels.defaultCacheDirectory(for: version)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            Log.speech.info("deleted \(choice.engineName, privacy: .public)")
        } catch {
            Log.speech.error("couldn't delete \(choice.engineName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Preparing

    /// Downloads (if needed), loads and warms up the selected engine. Safe to call repeatedly;
    /// concurrent callers share one load. After a failure, calling it again is the retry.
    func prepare() async {
        guard !isPreview else { return }
        let choice = settings.engine

        if let loaded, loaded.choice == choice {
            state = .ready
            return
        }
        if let inflight, inflight.choice == choice {
            await inflight.task.value
            return
        }

        // Anything still preparing was for an engine that's no longer selected.
        cancelInflight()
        generation += 1
        let id = generation
        let previous = windingDown.removeValue(forKey: choice)
        let task = Task {
            await previous?.value
            await self.load(choice, id: id)
        }
        inflight = Inflight(id: id, choice: choice, task: task)
        await task.value
    }

    /// The ready engine for the current setting. Waits for `prepare()` if a load is running.
    ///
    /// Never strands a dictation that could be transcribed: while the selected Parakeet model is
    /// still downloading (or failed to load), the previously loaded engine, or Apple Speech,
    /// stands in, and History records which engine actually ran.
    func engine() async throws -> any TranscriptionEngine {
        guard !isPreview else { throw TranscriptionError.modelNotReady }
        let wanted = settings.engine
        if let loaded, loaded.choice == wanted { return loaded.engine }

        if (wanted == .apple || isDownloaded(wanted)), inflight == nil, case .failed = state {
            // It failed to load last time (a damaged model fails the same way again). Retry in
            // the background rather than making every dictation wait out a doomed load.
            Task { await self.prepare() }
        } else if wanted == .apple || isDownloaded(wanted) {
            // Seconds away at most, usually: worth waiting for, up to a limit.
            do {
                try await HardDeadline.run(within: Self.loadWaitLimit) { await self.prepare() }
            } catch {
                Log.speech.notice("\(wanted.engineName, privacy: .public) is still loading; using a stand-in for this dictation")
            }
            if let loaded, loaded.choice == wanted { return loaded.engine }
        } else if inflight == nil, case .failed = state {
            // A download isn't something to wait for mid-dictation. Retry the one that failed
            // and carry on with what's available. (One never started stays the user's call.)
            Task { await self.prepare() }
        }

        if let loaded {
            Log.speech.notice("using \(loaded.choice.engineName, privacy: .public) until \(wanted.engineName, privacy: .public) is ready")
            return loaded.engine
        }
        if wanted.isParakeet {
            Log.speech.notice("using Apple Speech until \(wanted.engineName, privacy: .public) is ready")
            return fallbackEngine()
        }
        // `state` carries the reason (`.failed(message)`); callers word it for the HUD.
        throw TranscriptionError.modelNotReady
    }

    // MARK: - Loading

    private func load(_ choice: SpeechEngineChoice, id: Int) async {
        defer {
            if inflight?.id == id { inflight = nil }
        }
        do {
            let engine: any TranscriptionEngine
            if let version = choice.asrVersion {
                #if arch(x86_64)
                throw PreparationError.needsAppleSilicon
                #else
                if !isDownloaded(choice) {
                    try Self.ensureFreeSpace(for: choice, version: version)
                    update(.downloading(progress: nil), id: id)
                    try await download(version, id: id)
                }
                try Task.checkCancellation()
                update(.loading, id: id)
                let settings = self.settings
                engine = try await ParakeetEngine.load(
                    version,
                    name: choice.engineName,
                    booster: booster,
                    boostingEnabled: { await settings.vocabularyBoosting }
                )
                #endif
            } else {
                update(.loading, id: id)
                let apple = AppleSpeechEngine()
                try await apple.prepare()
                engine = apple
            }
            try Task.checkCancellation()
            guard inflight?.id == id else { return }

            loaded = Loaded(choice: choice, engine: engine)
            retriedWhileOnline = false
            stopWatchingConnectivity()
            state = .ready
            Log.speech.info("\(choice.engineName, privacy: .public) is ready")

            // Off the critical path: if the boosting model is already on disk, load it now so
            // the first dictation with dictionary words doesn't skip boosting. A missing one is
            // fetched lazily, the first time there are words to boost.
            if choice.isParakeet, settings.vocabularyBoosting, VocabularyBooster.isDownloaded {
                let booster = self.booster
                Task { await booster.prefetch() }
            }
        } catch {
            // Superseded or cancelled loads leave `state` to their replacement. A load that is
            // still current must always land somewhere: a stray CancellationError from deep in
            // the download stack would otherwise leave `.downloading` showing with nothing
            // running, and nothing to retry it.
            guard inflight?.id == id, !Task.isCancelled else { return }
            let message = Self.message(for: error, choice: choice)
            Log.speech.error("""
                \(choice.engineName, privacy: .public) failed to prepare: \
                \(error.localizedDescription, privacy: .public)
                """)
            state = .failed(message)
            if Self.isConnectivityFailure(error) { watchConnectivity() }
        }
    }

    // MARK: - Resuming after a network failure

    /// A download that failed because the network dropped resumes by itself when it returns,
    /// so onboarding on flaky Wi-Fi doesn't need babysitting. The Retry path (`prepare()`)
    /// still works at any time; this only saves the click.
    private func watchConnectivity() {
        guard connectivity == nil else { return }
        wentOffline = false
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = Self.pathHandler { [weak self] online in
            Task { @MainActor [weak self] in
                self?.connectivityChanged(online: online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.github.futurelevi.murmur.connectivity", qos: .utility))
        connectivity = monitor
    }

    /// Built outside the main actor on purpose. A closure written inline here would inherit
    /// main-actor isolation, and Network calls it on its own queue, which Swift 6 traps as an
    /// isolation violation at runtime.
    private nonisolated static func pathHandler(
        _ forward: @escaping @Sendable (Bool) -> Void
    ) -> @Sendable (NWPath) -> Void {
        { path in forward(path.status == .satisfied) }
    }

    private func connectivityChanged(online: Bool) {
        guard connectivity != nil else { return }
        guard case .failed = state else {
            stopWatchingConnectivity()
            return
        }
        guard online else {
            wentOffline = true
            return
        }
        // Back after an outage: resume promptly. Online all along means the server hiccuped:
        // one unhurried retry, then wait for the network to actually change.
        let delay: Duration
        if wentOffline {
            delay = .seconds(2)
        } else if !retriedWhileOnline {
            retriedWhileOnline = true
            delay = .seconds(20)
        } else {
            return
        }
        stopWatchingConnectivity()
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, case .failed = self.state else { return }
            Log.speech.info("network is back; resuming the model download")
            await self.prepare()
        }
    }

    private func stopWatchingConnectivity() {
        connectivity?.cancel()
        connectivity = nil
        wentOffline = false
    }

    private static func isConnectivityFailure(_ error: Error) -> Bool {
        if let download = error as? DownloadError {
            if case .downloadFailed(_, let underlying) = download { return isConnectivityFailure(underlying) }
            if case .stalled = download { return true }
            if case .invalidResponse = download { return true }
            if case .htmlErrorResponse = download { return true }
            if case .rateLimited = download { return true }
            return false
        }
        return (error as NSError).domain == NSURLErrorDomain
    }

    /// Downloads with live, byte-weighted progress from FluidAudio's `ProgressHandler`.
    private func download(_ version: AsrModelVersion, id: Int) async throws {
        // The handler fires on FluidAudio's queues, often; a newest-only buffer coalesces bursts
        // and keeps the updates in order on the main actor.
        let (events, sink) = AsyncStream<DownloadProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let watcher = Task { [weak self] in
            for await event in events {
                self?.apply(event, id: id)
            }
        }
        defer {
            sink.finish()
            watcher.cancel()
        }
        try await AsrModels.download(version: version, progressHandler: { sink.yield($0) })
    }

    private func apply(_ event: DownloadProgress, id: Int) {
        guard inflight?.id == id else { return }
        if case .compiling = event.phase {
            if case .downloading = state { state = .loading }
            return
        }
        // `totalFiles == 0` is FluidAudio's "already cached" report for later files; only a
        // real transfer moves the bar.
        guard case .downloading(_, let totalFiles) = event.phase, totalFiles > 0,
              case .downloading(let shown) = state
        else { return }

        let fraction = min(1, max(0, event.fractionCompleted / Self.downloadPhaseWeight))
        let previous = shown ?? 0
        // Monotonic, and only in visible steps: SwiftUI needn't redraw for every packet.
        guard fraction >= previous + 0.004 || (fraction >= 1 && previous < 1) || shown == nil else { return }
        state = .downloading(progress: max(previous, fraction))
    }

    private func update(_ newState: State, id: Int) {
        guard inflight?.id == id else { return }
        state = newState
    }

    private func cancelInflight() {
        guard let inflight else { return }
        inflight.task.cancel()
        windingDown[inflight.choice] = inflight.task
        self.inflight = nil
    }

    private func fallbackEngine() -> any TranscriptionEngine {
        if let appleFallback { return appleFallback }
        let engine = AppleSpeechEngine()
        appleFallback = engine
        return engine
    }

    // MARK: - Settings

    /// Picking another engine in Settings starts preparing it right away, so `state` always
    /// describes what's selected and the menu bar can show its progress.
    private func observeEngineSetting() {
        withObservationTracking {
            _ = settings.engine
        } onChange: { [weak self] in
            // Fires before the new value is stored; hop so the handler reads the new one.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeEngineSetting()
                self.engineSettingChanged()
            }
        }
    }

    private func engineSettingChanged() {
        let choice = settings.engine
        if let loaded, loaded.choice == choice {
            // Switched back to the engine that's still loaded: nothing to fetch.
            cancelInflight()
            state = .ready
            return
        }
        guard inflight?.choice != choice else { return }
        Task { await self.prepare() }
    }

    // MARK: - Messages

    private enum PreparationError: LocalizedError {
        case needsAppleSilicon
        case notEnoughSpace(engine: String, size: String)

        var errorDescription: String? {
            switch self {
            case .needsAppleSilicon:
                "Parakeet needs a Mac with Apple silicon. Choose Apple Speech in Settings instead."
            case .notEnoughSpace(let engine, let size):
                "There isn't enough free disk space for \(engine). It needs \(size); free some space and try again."
            }
        }
    }

    /// Bytes each model needs on disk, with headroom (Ultra's int8 encoder alone is 595 MB).
    private static func requiredBytes(for choice: SpeechEngineChoice) -> Int64 {
        choice == .parakeetUltra ? 680_000_000 : 540_000_000
    }

    /// Fails before a download that can't fit, rather than minutes into one. Bytes already on
    /// disk from an interrupted attempt count toward the total.
    private static func ensureFreeSpace(for choice: SpeechEngineChoice, version: AsrModelVersion) throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let values = try? support.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return }
        let present = allocatedSize(of: AsrModels.defaultCacheDirectory(for: version)) ?? 0
        if available + present < requiredBytes(for: choice) {
            throw PreparationError.notEnoughSpace(engine: choice.engineName, size: choice.downloadSize)
        }
    }

    /// A sentence a person can act on, never a raw framework error.
    private static func message(for error: Error, choice: SpeechEngineChoice) -> String {
        if let preparation = error as? PreparationError, let description = preparation.errorDescription {
            return description
        }
        if let transcription = error as? TranscriptionError, let description = transcription.errorDescription {
            return description
        }
        if let download = error as? DownloadError {
            if case .downloadFailed(_, let underlying) = download {
                return message(for: underlying, choice: choice)
            }
            if case .stalled = download {
                return "The download stalled. Try again and it will pick up where it left off."
            }
            if case .rateLimited = download {
                return "The download server is busy. Try again in a few minutes."
            }
            return "The \(choice.engineName) download didn't finish. Try again and it will pick up where it left off."
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed:
                return "Murmur couldn't reach the download server. Check your connection and try again; the download will pick up where it left off."
            default:
                return "The \(choice.engineName) download failed. Try again and it will pick up where it left off."
            }
        }
        if (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC)) {
            return "There isn't enough free disk space for \(choice.engineName). It needs \(choice.downloadSize)."
        }
        if error is AsrModelsError || error is ASRError {
            return "\(choice.engineName) couldn't be loaded. Try again; if it keeps failing, choose another engine in Settings and delete this one to download it fresh."
        }
        return "\(choice.engineName) couldn't be prepared: \(error.localizedDescription)"
    }

    // MARK: - Files

    /// An interrupted download leaves `*.partial` staging files inside an otherwise
    /// complete-looking `.mlmodelc`; those aren't usable models yet.
    private static func containsPartialDownload(_ directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        while let item = enumerator.nextObject() as? URL {
            if item.pathExtension == "partial" { return true }
        }
        return false
    }

    private static func allocatedSize(of directory: URL) -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard FileManager.default.fileExists(atPath: directory.path),
              let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys)
        else { return nil }
        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total > 0 ? total : nil
    }
}

fileprivate extension SpeechEngineChoice {
    /// The FluidAudio model behind each Parakeet choice; `nil` for Apple Speech.
    var asrVersion: AsrModelVersion? {
        switch self {
        case .parakeetUltra: .ultra
        case .parakeetV3: .v3
        case .parakeetV2: .v2
        case .apple: nil
        }
    }

    /// The engine name History records.
    var engineName: String {
        switch self {
        case .parakeetUltra: "Parakeet Ultra"
        case .parakeetV3: "Parakeet v3"
        case .parakeetV2: "Parakeet v2"
        case .apple: "Apple Speech"
        }
    }
}
