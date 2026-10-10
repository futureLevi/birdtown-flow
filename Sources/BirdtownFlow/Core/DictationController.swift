import AVFoundation
import AppKit
import Carbon.HIToolbox
import Foundation
import MurmurDictionary
import MurmurKit
import Observation

/// The dictation state machine: hotkey → record → transcribe → polish → insert → history.
///
/// Every path ends back at `.idle`: transient phases (`done`, `cancelled`, `failed`) reset on
/// a timer, and each await that could hang (model load, transcription, polish) runs under a
/// `Watchdog`. Audio is written and a History row exists before transcription starts, so a
/// crash or an engine failure never loses what was said.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        /// Microphone open, capturing.
        case listening
        /// Key released; the speech engine is running.
        case transcribing
        /// AI polish is rewriting the transcript.
        case polishing
        /// Text was inserted (or copied). Shown briefly, then back to idle.
        case done
        /// The user pressed Esc. Shown briefly, then back to idle.
        case cancelled
        /// Shown briefly with a short message, then back to idle.
        case failed(String)

        var isRecording: Bool { self == .listening }
        var isBusy: Bool { self == .transcribing || self == .polishing }
    }

    /// The next step a finished dictation's message points to. Clicking the HUD's message
    /// pill takes it (see `HUDController`); `nil` means the pill isn't clickable.
    enum FollowUp: Equatable, Sendable {
        /// The dictation's History row: its audio, Retry, and any polish note.
        case record(UUID)
        /// System Settings › Privacy & Security › Microphone.
        case microphoneAccess
        /// System Settings › Privacy & Security › Accessibility.
        case accessibilityAccess
        /// Birdtown Flow's microphone picker (Settings › Audio & Speech).
        case inputDevice
    }

    /// Gesture and display timings. The HUD and UI read these rather than guessing.
    enum Timing {
        /// A press becomes a dictation (sound, HUD) only after this long without another key:
        /// fn+← and ⌥+letter are shortcuts, and must never flash the HUD or chime. The
        /// microphone is already capturing during the grace, so no syllable is lost.
        static let chordGrace: Duration = .milliseconds(150)
        /// A release sooner than this isn't a dictation: half a double-tap, or a slip.
        static let shortTap: TimeInterval = 0.25
        /// After a short tap, how long a second press has to arrive to lock hands-free.
        static let doubleTapWindow: Duration = .milliseconds(350)
        /// Recordings shorter than this are dropped without a trace.
        static let minimumAudio: Double = 0.3
        /// A recording whose loudest 33 ms window stays below this meter level (≈ −47 dBFS)
        /// heard nothing…
        static let silenceLevel: Float = 0.06
        /// …and if it lasted at least this long it was deliberate, so the HUD says the mic
        /// heard nothing. Shorter silent ones are dropped without a trace.
        static let noSpeechNotice: Double = 1.0
        static let doneDisplay: Duration = .milliseconds(800)
        /// Longer than `doneDisplay`, so the "copied" notice can be read.
        static let copiedDisplay: Duration = .milliseconds(2200)
        static let cancelledDisplay: Duration = .milliseconds(500)
        /// Long enough to read a two-line message and reach for the pill to act on it.
        static let failedDisplay: Duration = .milliseconds(4000)
        /// A message the pointer was holding open stays this long after the pointer leaves.
        static let hoverLinger: Duration = .milliseconds(1200)
        /// Closing the microphone and collecting its samples.
        static let recorderStop: Duration = .seconds(5)
        /// Waiting for a model that's still loading.
        static let modelWait: Duration = .seconds(30)
        /// Speech to text: at least a minute, more for a long recording, by how fast `engine`
        /// is (`TranscriptionTimeLimit`), so a slow Mac doesn't fail a long dictation, or its
        /// Retry, that is still being transcribed.
        static func transcription(samples: Int, engine: any TranscriptionEngine) -> Duration {
            let kind: TranscriptionTimeLimit.Engine = engine is AppleSpeechEngine ? .appleSpeech : .parakeet
            let audioSeconds = Double(samples) / AudioRecorder.sampleRate
            return .seconds(TranscriptionTimeLimit.seconds(audioSeconds: audioSeconds, engine: kind))
        }
        /// Added to PolishService's limit for the text (`PolishService.overallTimeLimit(for:using:)`)
        /// as a backstop to its own timeout.
        static let polishGrace: Double = 3
    }

    /// Number of samples kept in `levels`.
    static let levelHistoryCount = 48

    private(set) var phase: Phase = .idle
    /// Recording continues without holding the key; tap it again (or press Stop) to finish.
    private(set) var isHandsFree = false
    /// Smoothed microphone level, 0…1. Updated ~30×/s while listening.
    private(set) var level: Float = 0
    /// Recent levels, oldest first, for the waveform. Always `levelHistoryCount` long.
    private(set) var levels: [Float] = Array(repeating: 0, count: DictationController.levelHistoryCount)
    /// When the current recording started.
    private(set) var recordingStartedAt: Date?
    /// The app that had focus when recording started.
    private(set) var context: AppContext?
    /// The most recent finished dictation.
    private(set) var lastRecord: HistoryRecord?
    /// Whether the global hotkey is armed (false usually means Accessibility is missing).
    private(set) var isHotkeyActive = false
    /// Why the last dictation went to the clipboard instead of being typed ("Copied, since no
    /// text field was focused"). Set alongside `.done`, cleared at idle. `nil` when it was typed.
    private(set) var notice: String?
    /// Where clicking the HUD's message goes: set with `.failed` and notice-bearing `.done`,
    /// cleared at idle.
    private(set) var followUp: FollowUp?

    let settings: Settings
    let history: HistoryStore
    let snippets: SnippetStore
    let dictionary: DictionaryStore
    let lab: PolishLabStore
    let models: ModelManager

    // MARK: - Private state

    /// One press-to-release (or hands-free) recording.
    private struct Session {
        let generation: Int
        /// The History record this recording becomes, from key-down on.
        let id: UUID
        let startedAt: Date
        /// Whether the user has been told we're listening (phase, sound). False during the chord grace.
        var isVisible = false
        /// A short tap just ended; a second press within the window locks hands-free.
        var awaitingSecondTap = false
        /// Why recording can't happen (microphone denied, no device). Reported once the press
        /// proves deliberate, so a shortcut never produces an error.
        var blocked: String?
        let contextTask: Task<AppContext, Never>
        /// Work on a long recording while it's still going: windows transcribed, parts polished.
        var live: LiveDictation?
        var progressive: ProgressivePolisher?
    }

    /// What the key currently held down means.
    private enum PressRole {
        /// Nothing: pressed while busy, or already accounted for.
        case ignored
        /// Hold-to-talk: releasing it ends the recording.
        case hold
        /// The second press of a double-tap, which locked hands-free.
        case secondTap
        /// A tap that will finish a hands-free recording when released.
        case finishTap
    }

    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let hotkey = HotkeyMonitor()
    @ObservationIgnored private let pasteLastShortcut = GlobalShortcut()
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pressRole = PressRole.ignored
    @ObservationIgnored private var pressStartedAt = Date.distantPast
    @ObservationIgnored private var armTask: Task<Void, Never>?
    @ObservationIgnored private var doubleTapTask: Task<Void, Never>?
    @ObservationIgnored private var phaseResetTask: Task<Void, Never>?
    /// The pointer is resting on the message pill, so it stays until the pointer leaves.
    @ObservationIgnored private var isFeedbackHeld = false
    @ObservationIgnored private var rearmTask: Task<Void, Never>?
    /// The dictation being finished (stop → transcribe → insert). `nil` once it's done or cancelled.
    @ObservationIgnored private var processing: (id: UUID, task: Task<Void, Never>)?
    /// Between key-up and the transcribing phase, while the recorder hands over its samples.
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var accessibilityObserver: (any NSObjectProtocol)?

    private static let silentLevels = Array(repeating: Float(0), count: levelHistoryCount)

    init(
        settings: Settings,
        history: HistoryStore,
        snippets: SnippetStore,
        dictionary: DictionaryStore,
        lab: PolishLabStore,
        models: ModelManager
    ) {
        self.settings = settings
        self.history = history
        self.snippets = snippets
        self.dictionary = dictionary
        self.lab = lab
        self.models = models

        recorder.setEventHandler { [weak self] event in
            Task { @MainActor in self?.handleAudio(event) }
        }
        hotkey.handler = { [weak self] event in
            self?.handleHotkey(event) ?? false
        }
        hotkey.onTapLost = { [weak self] in
            guard let self else { return }
            // A hold in progress will never see its release now.
            if self.session != nil, !self.isHandsFree { self.discardSession() }
            self.isHotkeyActive = false
            self.scheduleRearm()
        }
    }

    // MARK: - Lifecycle

    /// Arms the hotkeys. Returns `false` when the event tap couldn't be created; in that case
    /// it keeps retrying quietly and arms itself as soon as Accessibility is granted.
    @discardableResult
    func activate() -> Bool {
        hotkey.watchesControlOption = settings.handsFreeShortcut == .controlOption
        hotkey.handsFreeChord = settings.activeHandsFreeChord
        if !hotkey.isArmed || hotkey.key != settings.pushToTalkKey {
            restartHotkey()
        }
        isHotkeyActive = hotkey.isArmed
        if isHotkeyActive {
            rearmTask?.cancel()
            rearmTask = nil
        } else {
            scheduleRearm()
        }
        registerPasteLastShortcut()
        observeAccessibilityGrant()
        if Permissions.hasMicrophone {
            recorder.prewarm(deviceUID: settings.inputDeviceUID)
        }
        return isHotkeyActive
    }

    func deactivate() {
        rearmTask?.cancel()
        rearmTask = nil
        if session != nil { cancel() }
        hotkey.stop()
        isHotkeyActive = false
        pasteLastShortcut.unregister()
    }

    /// Re-reads shortcut settings (push-to-talk key, hands-free, paste-last) and re-arms.
    func reloadShortcuts() {
        hotkey.watchesControlOption = settings.handsFreeShortcut == .controlOption
        hotkey.handsFreeChord = settings.activeHandsFreeChord
        if hotkey.key != settings.pushToTalkKey || !hotkey.isArmed {
            restartHotkey()
            isHotkeyActive = hotkey.isArmed
            if !isHotkeyActive { scheduleRearm() }
        }
        registerPasteLastShortcut()
        if Permissions.hasMicrophone, session == nil {
            recorder.prewarm(deviceUID: settings.inputDeviceUID)
        }
    }

    private func restartHotkey() {
        // Restarting the tap forgets a held key, so its release would never arrive and a
        // hold-to-talk recording would be orphaned. Drop it (hands-free ones need no key).
        if session != nil, !isHandsFree { discardSession() }
        pressRole = .ignored
        hotkey.key = settings.pushToTalkKey
        hotkey.start()
    }

    /// Polls cheaply (every 2 s) until the tap can be created. Covers grants made while no
    /// settings window is polling `PermissionsMonitor`. While Accessibility is reported granted
    /// but macOS still refuses the tap (it sometimes wants a fresh process), retries back off
    /// to once a minute and the failure is logged only when the interval grows; a fresh grant
    /// notification restarts the loop at 2 s.
    private func scheduleRearm() {
        guard rearmTask == nil else { return }
        rearmTask = Task { [weak self] in
            let poll: Duration = .seconds(2)
            var delay = poll
            var failDelay = poll
            while !Task.isCancelled {
                try? await Task.sleep(for: delay, tolerance: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard Permissions.hasAccessibility else {
                    delay = poll
                    failDelay = poll
                    continue
                }
                self.hotkey.key = self.settings.pushToTalkKey
                if self.hotkey.start(logFailure: false) {
                    self.isHotkeyActive = true
                    self.rearmTask = nil
                    Log.hotkey.info("armed after Accessibility was granted")
                    return
                }
                delay = failDelay
                let next = min(failDelay * 2, .seconds(60))
                if next != failDelay {
                    let seconds = delay.components.seconds
                    Log.hotkey.error("tapCreate refused with Accessibility granted; retrying in \(seconds) s")
                }
                failDelay = next
            }
        }
    }

    private func observeAccessibilityGrant() {
        guard accessibilityObserver == nil else { return }
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: PermissionsMonitor.accessibilityGranted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Restart a backed-off rearm loop at its fastest interval.
                self.rearmTask?.cancel()
                self.rearmTask = nil
                _ = self.activate()
            }
        }
    }

    private func registerPasteLastShortcut() {
        guard settings.pasteLastShortcutEnabled else {
            pasteLastShortcut.unregister()
            return
        }
        let chord = settings.pasteLastShortcut
        guard pasteLastShortcut.registeredChord != chord else { return }
        pasteLastShortcut.register(chord) { [weak self] in
            self?.pasteLast()
        }
    }

    // MARK: - Recording

    /// Start (hands-free) from a button, or stop if already recording.
    func toggleRecording() {
        if let session {
            if session.isVisible { stopRecording() }
            return
        }
        startRecording(handsFree: true)
    }

    func startRecording(handsFree: Bool) {
        guard session == nil, !phase.isBusy, !isStopping else { return }
        pressRole = .ignored
        beginSession(visible: true, handsFree: handsFree)
    }

    /// Finish the recording and process it.
    func stopRecording() {
        guard let current = session else { return }
        session = nil
        armTask?.cancel()
        armTask = nil
        doubleTapTask?.cancel()
        doubleTapTask = nil

        if let blocked = current.blocked {
            endLive(current)
            recorder.cancel()
            fail(blocked, followUp: blockedFollowUp())
            return
        }
        // Normally visible by now; if the announcement was delayed (a busy main thread), the
        // hold was still long enough to be deliberate, so process it rather than drop it.

        isStopping = true
        let releasedAt = Date()
        let id = current.id
        let task = Task { [weak self] in
            guard let self else { return }
            await self.finish(current, releasedAt: releasedAt, id: id)
        }
        processing = (id, task)
    }

    /// Discard the recording without inserting anything.
    func cancel() {
        if let current = session {
            session = nil
            armTask?.cancel()
            armTask = nil
            doubleTapTask?.cancel()
            doubleTapTask = nil
            endLive(current)
            recorder.cancel()
            if current.isVisible {
                Sounds.play(.cancel)
                showTransient(.cancelled, for: Timing.cancelledDisplay)
            } else {
                resetToIdle()
            }
            return
        }
        if let processing {
            processing.task.cancel()
            self.processing = nil
            isStopping = false
            Sounds.play(.cancel)
            showTransient(.cancelled, for: Timing.cancelledDisplay)
        }
    }

    private func beginSession(visible: Bool, handsFree: Bool) {
        phaseResetTask?.cancel()
        phaseResetTask = nil
        if phase != .idle { phase = .idle }
        notice = nil
        followUp = nil
        isFeedbackHeld = false

        generation += 1
        let generation = generation

        // The microphone first: it's the only step where a delay costs the user words.
        var blocked: String?
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            recorder.start(deviceUID: settings.inputDeviceUID, generation: generation)
        case .notDetermined:
            blocked = "Allow microphone access, then try again"
        default:
            blocked = "Birdtown Flow needs microphone access"
        }

        let (quick, pid) = FrontmostContext.quick()
        context = quick
        // Claude Code takes a second or two to start; do it while the person is talking.
        prewarmPolish(for: quick)
        // The other providers warm up too: Apple's model loads, a cloud connection opens.
        if blocked == nil { warmUpPolish(for: quick) }
        let contextTask = Task.detached(priority: .userInitiated) {
            FrontmostContext.refined(quick, pid: pid)
        }

        level = 0
        levels = Self.silentLevels
        recordingStartedAt = Date()
        isHandsFree = handsFree
        let id = UUID()
        let startedAt = Date()
        session = Session(
            generation: generation, id: id, startedAt: startedAt, blocked: blocked, contextTask: contextTask
        )
        if blocked == nil, settings.liveTranscription {
            startLive(generation: generation, id: id, contextTask: contextTask, startedAt: startedAt)
        }

        if visible {
            announce(cue: .start)
        } else {
            armTask = Task { [weak self] in
                try? await Task.sleep(for: Timing.chordGrace)
                guard let self, !Task.isCancelled, self.session?.generation == generation else { return }
                self.announce(cue: .start)
            }
        }
    }

    /// The press is deliberate: show the HUD and chime — or, if recording can't happen, say why.
    private func announce(cue: Sounds.Cue) {
        guard var current = session, !current.isVisible else { return }
        armTask?.cancel()
        armTask = nil

        if let blocked = current.blocked {
            session = nil
            // A microphone that failed during the chord grace blocks a session that had started.
            endLive(current)
            recorder.cancel()
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                Task { _ = await Permissions.requestMicrophone() }
            }
            fail(blocked, followUp: blockedFollowUp())
            return
        }

        current.isVisible = true
        session = current
        phase = .listening
        Sounds.play(cue)
    }

    /// Drops the recording without a sound or a History row (shortcut chords, slips, a
    /// double-tap that never came).
    private func discardSession() {
        guard let current = session else { return }
        session = nil
        endLive(current)
        armTask?.cancel()
        armTask = nil
        doubleTapTask?.cancel()
        doubleTapTask = nil
        recorder.cancel()
        resetToIdle()
    }

    // MARK: - Long recordings

    /// Starts the work a long recording does before key-up: transcribing windows
    /// (`LiveDictation`) and polishing the finished parts (`ProgressivePolisher`).
    private func startLive(generation: Int, id: UUID, contextTask: Task<AppContext, Never>, startedAt: Date) {
        let live = LiveDictation(
            id: id, generation: generation, recorder: recorder, models: models, history: history,
            settings: settings,
            vocabulary: { [unowned self] in
                self.settings.vocabularyBoosting ? self.dictionary.biasPhrases : []
            },
            placeholder: { [unowned self] in
                let context = await contextTask.value
                return self.makeRecord(id: id, startedAt: startedAt, context: context, audioDuration: 0)
            }
        )
        let progressive = makeProgressivePolisher(contextTask: contextTask)
        if let progressive {
            live.onCommittedText = { [weak progressive] text in progressive?.committedTextDidChange(text) }
        }
        session?.live = live
        session?.progressive = progressive
        live.start()
    }

    /// The polisher for a long recording's finished parts, or `nil` when it won't be used.
    /// It starts once the frontmost context, and so the style and its Lab configuration, is
    /// known; a style whose configuration turns polish off leaves it idle.
    private func makeProgressivePolisher(contextTask: Task<AppContext, Never>) -> ProgressivePolisher? {
        guard settings.polishWhileSpeaking, settings.polishInParts, settings.polishProvider != .off else { return nil }
        let progressive = ProgressivePolisher(service: PolishService(settings: settings), settings: settings)
        Task { [weak self, weak progressive] in
            let context = await contextTask.value
            guard let self, let progressive else { return }
            let style = self.settings.style(for: context.category)
            let configuration = self.lab.configuration(for: style)
            guard (configuration?.provider ?? self.settings.polishProvider) != .off else { return }
            // The request key-up will make for each part, but for its text (`polishStage`).
            progressive.configure(
                template: self.polishRequest(text: "", style: style, context: context, configuration: configuration),
                configuration: configuration,
                options: self.currentPipelineOptions
            )
        }
        return progressive
    }

    /// The recording is gone (Esc, discarded, dropped, failed): stop its work and leave no trace.
    private func endLive(_ session: Session) {
        session.live?.cancel()
        session.progressive?.cancel()
    }

    private func lockHandsFree() {
        guard let current = session else { return }
        isHandsFree = true
        if current.isVisible {
            Sounds.play(.lock)
        } else {
            announce(cue: .lock)
        }
    }

    // MARK: - Hotkey gestures

    private func handleHotkey(_ event: HotkeyMonitor.Event) -> Bool {
        switch event {
        case .keyDown:
            keyDown()
            return false
        case .keyUp:
            keyUp()
            return false
        case .chord:
            chord()
            return false
        case .space:
            return lockFromSpace()
        case .escape:
            return escapePressed()
        case .controlOptionTap:
            handsFreeShortcutTapped()
            return false
        }
    }

    private func keyDown() {
        pressStartedAt = Date()
        pressRole = .ignored
        // Presses while processing are ignored, release included.
        if phase.isBusy || isStopping { return }

        if var current = session {
            if current.awaitingSecondTap {
                current.awaitingSecondTap = false
                session = current
                doubleTapTask?.cancel()
                doubleTapTask = nil
                pressRole = .secondTap
                lockHandsFree()
            } else {
                pressRole = .finishTap
            }
            return
        }

        pressRole = .hold
        beginSession(visible: false, handsFree: false)
    }

    private func keyUp() {
        let role = pressRole
        pressRole = .ignored

        switch role {
        case .ignored, .secondTap:
            return
        case .finishTap:
            stopRecording()
        case .hold:
            // Locked with Space while held: the release changes nothing.
            guard var current = session, !isHandsFree else { return }
            if Date().timeIntervalSince(pressStartedAt) >= Timing.shortTap {
                stopRecording()
                return
            }
            // Only a double-tap makes a quick press mean anything.
            guard settings.handsFreeShortcut == .doubleTap else {
                discardSession()
                return
            }
            // A slip shorter than the chord grace stays invisible; a second press announces it.
            if !current.isVisible {
                armTask?.cancel()
                armTask = nil
            }
            current.awaitingSecondTap = true
            session = current
            let generation = current.generation
            doubleTapTask = Task { [weak self] in
                try? await Task.sleep(for: Timing.doubleTapWindow)
                guard let self, !Task.isCancelled,
                      let session = self.session, session.generation == generation, session.awaitingSecondTap
                else { return }
                self.discardSession()
            }
        }
    }

    /// Another key joined the push-to-talk key: a keyboard shortcut. Cancel without a trace.
    private func chord() {
        let role = pressRole
        pressRole = .ignored
        switch role {
        case .hold:
            if session != nil, !isHandsFree { discardSession() }
        case .secondTap:
            // "Tap, then fn+←" is navigation, not a double-tap.
            discardSession()
        case .finishTap, .ignored:
            break
        }
    }

    /// ⌃⌥ tapped, when that's the hands-free shortcut: start a hands-free recording, or
    /// finish the one in progress.
    private func handsFreeShortcutTapped() {
        guard settings.handsFreeShortcut == .controlOption else { return }
        if session != nil {
            if isHandsFree { stopRecording() }
            return
        }
        startRecording(handsFree: true)
    }

    private func lockFromSpace() -> Bool {
        guard settings.handsFreeEnabled, pressRole == .hold, session != nil, !isHandsFree else { return false }
        lockHandsFree()
        return true
    }

    private func escapePressed() -> Bool {
        switch phase {
        case .listening, .transcribing, .polishing:
            cancel()
            return true
        default:
            return false
        }
    }

    // MARK: - Audio events

    private func handleAudio(_ event: AudioRecorder.Event) {
        switch event {
        case .level(let value, let generation):
            guard session?.generation == generation else { return }
            // Fast attack, slower release: lively without flicker.
            level = value >= level ? value * 0.7 + level * 0.3 : value * 0.25 + level * 0.75
            var next = levels
            next.removeFirst()
            next.append(value)
            levels = next

        case .interrupted(let reason, let generation):
            guard let current = session, current.generation == generation else { return }
            switch reason {
            case .deviceChanged: Log.audio.notice("input changed mid-recording — finishing with what was captured")
            case .timeLimit: Log.audio.notice("recording hit the time limit — finishing")
            }
            if current.isVisible { stopRecording() } else { discardSession() }

        case .failed(let error, let generation):
            guard var current = session, current.generation == generation else { return }
            let message = error == .noInputDevice ? "No microphone found" : "Couldn't start the microphone"
            if current.isVisible {
                session = nil
                armTask?.cancel()
                doubleTapTask?.cancel()
                endLive(current)
                fail(message, followUp: .inputDevice)
            } else {
                current.blocked = message
                session = current
            }
        }
    }

    // MARK: - Processing

    private func isCurrent(_ id: UUID) -> Bool { processing?.id == id }

    private func finish(_ session: Session, releasedAt: Date, id: UUID) async {
        // CoreAudio can wedge stopping a device that's being unplugged; never wait forever.
        let recorder = self.recorder
        let clock = ContinuousClock()
        let stopStart = clock.now
        let audio: CapturedAudio
        do {
            audio = try await Watchdog.run(within: Timing.recorderStop) { await recorder.stop() }
        } catch {
            endLive(session)
            guard isCurrent(id) else { return }
            Log.audio.error("the recorder didn't hand over its audio in time")
            isStopping = false
            processing = nil
            fail("The microphone stopped responding", followUp: .inputDevice)
            return
        }
        guard isCurrent(id) else {
            endLive(session)
            return
        }
        var timing = TimingLine("dictation \(id.uuidString.prefix(8))")
        timing.seconds("audio", audio.duration)
        timing.tag("engine", settings.engine.rawValue)
        timing.ms("stop", Self.milliseconds(stopStart.duration(to: clock.now)))
        isStopping = false
        isHandsFree = false
        level = 0

        switch DictationFeedback.classify(
            duration: audio.duration,
            peakLevel: audio.peakLevel,
            minimumAudio: Timing.minimumAudio,
            silenceLevel: Timing.silenceLevel,
            noSpeechNotice: Timing.noSpeechNotice
        ) {
        case .drop:
            Log.audio.info("dropped: \(audio.duration, format: .fixed(precision: 2))s, peak \(audio.peakLevel, format: .fixed(precision: 2))")
            endLive(session)
            processing = nil
            resetToIdle()
            return
        case .noSpeech:
            // Held long enough to mean it, and the mic heard nothing: a muted or wrong input
            // (AirPods that just connected). Say so, rather than look like a missed hotkey.
            Log.audio.info("no speech: \(audio.duration, format: .fixed(precision: 2))s, peak \(audio.peakLevel, format: .fixed(precision: 2))")
            endLive(session)
            processing = nil
            fail(DictationFeedback.noSpeechMessage(deviceName: inputDeviceName()), followUp: .inputDevice)
            return
        case .speech:
            break
        }

        Sounds.play(.stop)
        phase = .transcribing
        let contextStart = clock.now
        let context = await session.contextTask.value
        timing.ms("context", Self.milliseconds(contextStart.duration(to: clock.now)))
        guard isCurrent(id) else {
            endLive(session)
            return
        }
        self.context = context
        // Stop cutting windows; one already being decoded keeps going for `process` to use.
        if let live = session.live {
            let liveStopStart = clock.now
            await live.stop()
            timing.ms("liveStop", Self.milliseconds(liveStopStart.duration(to: clock.now)))
            guard isCurrent(id) else {
                endLive(session)
                return
            }
        }
        await process(
            audio, context: context, startedAt: session.startedAt, releasedAt: releasedAt, id: id,
            live: session.live, progressive: session.progressive, timing: timing
        )
    }

    /// `timing` already holds what `finish` measured (stop, context, live stop); the summary
    /// line goes to `Log.timing` however processing ends.
    private func process(
        _ audio: CapturedAudio, context: AppContext, startedAt: Date, releasedAt: Date, id: UUID,
        live: LiveDictation?, progressive: ProgressivePolisher?, timing initialTiming: TimingLine
    ) async {
        let style = settings.style(for: context.category)
        var record = makeRecord(id: id, startedAt: startedAt, context: context, audioDuration: audio.duration)
        let clock = ContinuousClock()
        var timing = initialTiming
        defer {
            // Nothing polishes this dictation's parts any more.
            progressive?.cancel()
            timing.ms("total", Self.milliseconds(since: releasedAt))
            timing.tag("outcome", record.outcome.rawValue)
            Log.timing.notice("\(timing.text, privacy: .public)")
        }

        // Audio first: from here on, a crash or an engine failure must not lose what was said.
        // The same URL as any WAV written while recording, which this replaces in one piece.
        let url = history.newRecordingURL(for: id)
        let samples = audio.samples
        let wavStart = clock.now
        do {
            try await Task.detached(priority: .userInitiated) {
                try AudioRecorder.writeWAV(samples, to: url)
            }.value
            record.audioFileName = url.lastPathComponent
        } catch {
            Log.audio.error("couldn't save the recording: \(error.localizedDescription, privacy: .public)")
        }
        timing.ms("wav", Self.milliseconds(wavStart.duration(to: clock.now)))
        // Adds the row, or replaces the placeholder a long recording saved before key-up.
        let rowStart = clock.now
        history.update(record)
        live?.handOff()
        timing.ms("row", Self.milliseconds(rowStart.duration(to: clock.now)))

        do {
            guard isCurrent(id) else { throw CancellationError() }
            // `record.engine` starts as the selected engine and becomes the one that actually ran
            // (Apple Speech stands in while Parakeet downloads), even if transcription then fails.
            let output = try await transcribeAndClean(
                samples, context: context, style: style, engineName: &record.engine,
                live: live, progressive: progressive, purpose: .dictation
            ) { [weak self] in
                if self?.isCurrent(id) == true { self?.phase = .polishing }
            }
            output.addStages(to: &timing)
            guard isCurrent(id) else { throw CancellationError() }
            output.apply(to: &record)

            let text = output.result.text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                record.outcome = .empty
                record.errorMessage = nil
                record.timings.totalMs = Self.milliseconds(since: releasedAt)
                history.update(record)
                applyAudioRetention()
                processing = nil
                // Sound, but no words: say so, and point at the recording in History while
                // it's still there to play or retry ("Keep no audio" has just dropped it).
                let audioSaved = history.record(id: id)?.audioFileName != nil
                fail(DictationFeedback.noWordsMessage(audioSaved: audioSaved),
                     followUp: audioSaved ? .record(id) : nil)
                return
            }

            let insertStart = clock.now
            let outcome = await TextInjector.insert(text, restoreClipboard: settings.restoreClipboard)
            timing.ms("insert", Self.milliseconds(insertStart.duration(to: clock.now)))
            var copiedNotice: String?
            var copiedFollowUp: FollowUp?
            switch outcome {
            case .inserted:
                record.outcome = .inserted
            case .copied(let reason):
                record.outcome = .copied
                copiedNotice = reason.message
                copiedFollowUp = reason.followUp
            }
            // A polish fallback note ("timed out", "no API key") is the only message a
            // successful record carries.
            record.errorMessage = output.polishNote
            record.timings.totalMs = Self.milliseconds(since: releasedAt)
            history.update(record)
            applyAudioRetention()
            // Re-read: retention may just have dropped the audio file.
            lastRecord = history.record(id: id) ?? record

            // Insertion awaits (paste, clipboard restore), and Esc is live meanwhile. If this
            // dictation was cancelled or a new one began, the text is in and recorded, but the
            // phase, sounds and `processing` now belong to whatever came next: touching them
            // would flash "done" over a live recording or orphan the next dictation.
            guard isCurrent(id) else { return }
            // Where the text went matters most, so a "copied" notice wins over a polish note.
            // Text left on the clipboard is pasted with ⌘V, so that pill only becomes a link
            // when there's something to fix (Accessibility); opening a window would take the
            // paste target away.
            var resultFollowUp: FollowUp?
            if let copiedNotice {
                notice = copiedNotice
                resultFollowUp = copiedFollowUp
            } else if let polishNotice = DictationFeedback.polishNotice(for: output.polishNote) {
                notice = polishNotice
                resultFollowUp = .record(id)
            }
            processing = nil
            Sounds.play(.done)
            showTransient(.done, for: notice == nil ? Timing.doneDisplay : Timing.copiedDisplay,
                          followUp: resultFollowUp)
        } catch is CancellationError {
            // `cancel()` already moved the phase on; just record what happened.
            record.outcome = .cancelled
            record.errorMessage = nil
            history.update(record)
        } catch {
            let failure = self.message(for: error)
            Log.speech.error("dictation failed: \(String(describing: error), privacy: .public)")
            record.outcome = .failed
            record.errorMessage = failure
            record.timings.totalMs = Self.milliseconds(since: releasedAt)
            history.update(record)
            lastRecord = record
            guard isCurrent(id) else { return }
            processing = nil
            // The audio is saved; History is where Retry lives.
            fail(failure, followUp: .record(id))
        }
    }

    /// A dictation's History row before anything is known but its audio: it reads
    /// "Interrupted" until processing settles it, so a crash leaves an honest record.
    private func makeRecord(id: UUID, startedAt: Date, context: AppContext, audioDuration: Double) -> HistoryRecord {
        HistoryRecord(
            id: id,
            createdAt: startedAt,
            context: context,
            style: settings.style(for: context.category),
            engine: settings.engine.displayName,
            audioDuration: audioDuration,
            outcome: .failed,
            errorMessage: "Interrupted"
        )
    }

    /// What the speech engine and the text pipeline made of one recording.
    private struct PipelineOutput {
        var engineName: String
        var raw: String
        /// Words the engine's vocabulary boosting rewrote before `raw` came back.
        var boosted: [AppliedCorrection]
        var result: PipelineResult
        var polishedBy: PolishProvider?
        var polishNote: String?
        /// The Lab configuration this style used, by name.
        var polishConfiguration: String?
        /// From key-up's point of view: engine wait included, as History has always shown it.
        var transcribeMs: Int
        var polishMs: Int
        /// The timing summary's breakdown of the same work.
        var engineWaitMs: Int
        var transcriptionReport: TranscriptionReport
        /// `nil` when polish didn't run.
        var polishReport: PolishReport?
        var prepareMs: Int
        var finalizeMs: Int

        /// Appends engine wait, transcription, prepare, polish and finalize to the summary.
        func addStages(to line: inout TimingLine) {
            line.ms("engineWait", engineWaitMs)
            line.ms("transcribe", transcribeMs - engineWaitMs)
            line.tag("path", transcriptionReport.path.rawValue)
            if let reason = transcriptionReport.fallbackReason { line.tag("fallback", reason) }
            line.group("transcribe", transcriptionReport.line)
            line.ms("prepare", prepareMs)
            if let polishReport {
                line.ms("polish", polishMs)
                line.group("polish", polishReport.line)
            }
            line.ms("finalize", finalizeMs)
        }

        func apply(to record: inout HistoryRecord) {
            record.engine = engineName
            record.rawText = raw
            record.finalText = result.text
            // Boosting first: it ran first, on the audio, before any text step. The same pair
            // from both steps is one row (History lists them by value), with the counts added.
            var corrections: [AppliedCorrection] = []
            for correction in boosted + result.corrections {
                if let index = corrections.firstIndex(where: { $0.from == correction.from && $0.to == correction.to }) {
                    let merged = corrections[index]
                    corrections[index] = AppliedCorrection(from: merged.from, to: merged.to,
                                                           count: merged.count + correction.count)
                } else {
                    corrections.append(correction)
                }
            }
            record.corrections = corrections
            record.snippets = result.snippets
            record.polishedBy = polishedBy
            record.polishConfiguration = polishConfiguration
            record.timings.transcribeMs = transcribeMs
            record.timings.polishMs = polishMs
        }
    }

    /// engine → `TextPipeline.prepare` → optional polish → `TextPipeline.finalize`.
    ///
    /// `engineName` is set to the engine that runs as soon as it's chosen, so a failed record
    /// still names it.
    ///
    /// `live` and `progressive` hold the work a long recording did before key-up; a Retry has
    /// neither.
    private func transcribeAndClean(
        _ samples: [Float],
        context: AppContext,
        style: WritingStyle,
        engineName: inout String,
        live: LiveDictation?,
        progressive: ProgressivePolisher?,
        purpose: TranscriptionPurpose,
        willPolish: () -> Void
    ) async throws -> PipelineOutput {
        let clock = ContinuousClock()
        let transcribeStart = clock.now
        let engine = try await readyEngine()
        engineName = engine.displayName
        let engineWaitMs = Self.milliseconds(transcribeStart.duration(to: clock.now))
        let vocabulary = settings.vocabularyBoosting ? dictionary.biasPhrases : []
        let (transcript, transcriptionReport) = try await transcribeStage(
            samples, engine: engine, vocabulary: vocabulary, live: live, purpose: purpose
        )
        let raw = transcript.text
        let transcribeMs = Self.milliseconds(transcribeStart.duration(to: clock.now))
        try Task.checkCancellation()

        let prepareStart = clock.now
        var text = TextPipeline.prepare(raw, options: currentPipelineOptions)
        let prepareMs = Self.milliseconds(prepareStart.duration(to: clock.now))
        var polishedBy: PolishProvider?
        var polishNote: String?
        var polishConfiguration: String?
        var polishReport: PolishReport?
        var polishMs = 0

        if settings.polishProvider != .off, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            willPolish()
            let polishStart = clock.now
            let (outcome, report, configurationName) = await polishStage(
                text, style: style, context: context, progressive: progressive
            )
            text = outcome.text
            polishedBy = outcome.provider
            polishNote = outcome.note
            polishConfiguration = configurationName
            polishReport = report
            polishMs = Self.milliseconds(polishStart.duration(to: clock.now))
            try Task.checkCancellation()
        }

        let finalizeStart = clock.now
        let result = TextPipeline.finalize(
            text,
            style: style,
            corrector: dictionary.corrector,
            snippets: snippets.enabled,
            vocabulary: dictionary.biasPhrases
        )
        let finalizeMs = Self.milliseconds(finalizeStart.duration(to: clock.now))
        return PipelineOutput(
            engineName: engine.displayName,
            raw: raw,
            boosted: transcript.boosted,
            result: result,
            polishedBy: polishedBy,
            polishNote: polishNote,
            polishConfiguration: polishConfiguration,
            transcribeMs: transcribeMs,
            polishMs: polishMs,
            engineWaitMs: engineWaitMs,
            transcriptionReport: transcriptionReport,
            polishReport: polishReport,
            prepareMs: prepareMs,
            finalizeMs: finalizeMs
        )
    }

    /// Speech to text: today's whole-buffer call, or the windows of a long recording
    /// (`LongTranscription`), under the transcription watchdog.
    private func transcribeStage(
        _ samples: [Float],
        engine: any TranscriptionEngine,
        vocabulary: [String],
        live: LiveDictation?,
        purpose: TranscriptionPurpose
    ) async throws -> (Transcript, TranscriptionReport) {
        let transcriber = live?.transcriber
        let settings = self.settings
        // Scaled to the whole recording: a live dictation usually has only its tail left, but
        // any fallback transcribes all of it.
        let limit = Timing.transcription(samples: samples.count, engine: engine)
        return try await Watchdog.run(within: limit) {
            try await LongTranscription.transcript(
                samples, engine: engine, vocabulary: vocabulary,
                live: transcriber, purpose: purpose, settings: settings
            )
        }
    }

    /// AI polish of the prepared text, with the style's Lab configuration if it has one.
    private func polishStage(
        _ text: String,
        style: WritingStyle,
        context: AppContext,
        progressive: ProgressivePolisher?
    ) async -> (PolishService.Outcome, PolishReport, configurationName: String?) {
        // A style can be handed to a Lab configuration; the rest follow Settings.
        let configuration = lab.configuration(for: style)
        let request = polishRequest(text: text, style: style, context: context, configuration: configuration)
        let (outcome, report) = await polish(request, using: configuration, progressive: progressive)
        return (outcome, report, configuration?.name)
    }

    /// What `TextPipeline.prepare` does with the transcript, from Settings.
    private var currentPipelineOptions: PipelineOptions {
        PipelineOptions(removeFillers: settings.removeFillers, spokenCommands: settings.spokenCommands)
    }

    private func readyEngine() async throws -> any TranscriptionEngine {
        // No early exit while Parakeet downloads: `ModelManager.engine()` hands back Apple
        // Speech (or the previously loaded model) as a stand-in, so dictation works from the
        // first minute instead of after a 600 MB download.
        let models = self.models
        if case .notDownloaded = models.state {
            Task { await models.prepare() }
        }
        do {
            return try await Watchdog.run(within: Timing.modelWait) {
                try await models.engine()
            }
        } catch is Watchdog.Expired {
            throw DictationFailure(message: modelNotReadyMessage())
        } catch TranscriptionError.modelNotReady {
            throw DictationFailure(message: modelNotReadyMessage())
        }
    }

    /// Starts or stops the waiting Claude Code session after the polish settings, or the Lab's
    /// configurations or their styles, change.
    func polishSettingsChanged() {
        let context = self.context ?? AppContext(bundleID: nil, appName: nil, category: .other)
        if !prewarmPolish(for: context), !usesClaudeCode {
            ClaudeCodePolisher.shutDown()
        }
    }

    /// Whether any dictation could polish with Claude Code: Settings, or a Lab configuration
    /// some style uses.
    private var usesClaudeCode: Bool {
        guard settings.polishProvider != .off else { return false }
        return settings.polishProvider == .claudeCode
            || WritingStyle.allCases.contains { lab.configuration(for: $0)?.provider == .claudeCode }
    }

    /// Starts a Claude Code session for a dictation into `context`, if that's how it will be
    /// polished. Returns whether it is.
    @discardableResult
    private func prewarmPolish(for context: AppContext) -> Bool {
        guard settings.polishProvider != .off else { return false }
        let style = settings.style(for: context.category)
        let configuration = lab.configuration(for: style)
        guard (configuration?.provider ?? settings.polishProvider) == .claudeCode else { return false }
        // Only the text is unknown yet, and the instructions don't include it.
        let request = polishRequest(text: "", style: style, context: context, configuration: configuration)
        PolishService.claudeCode(model: configuration?.model, effort: configuration?.effort).prewarm(request)
        return true
    }

    /// Gets the polish provider for a dictation into `context` ready, unless it's Claude Code,
    /// which `prewarmPolish` starts. Only at key-down: a settings change doesn't warm anything.
    private func warmUpPolish(for context: AppContext) {
        guard settings.polishProvider != .off else { return }
        let style = settings.style(for: context.category)
        let configuration = lab.configuration(for: style)
        let request = polishRequest(text: "", style: style, context: context, configuration: configuration)
        PolishService(settings: settings).prewarm(request, using: configuration)
    }

    /// What polish gets for a dictation: Settings' cleanup level, or the instructions of the
    /// Lab configuration the style uses.
    private func polishRequest(
        text: String, style: WritingStyle, context: AppContext, configuration: PolishConfiguration?
    ) -> PolishRequest {
        PolishRequest(
            text: text,
            style: style,
            category: context.category,
            appName: context.appName,
            vocabulary: dictionary.biasPhrases,
            level: settings.polishLevel,
            instructions: configuration?.instructions
        )
    }

    /// PolishService never throws and has its own timeout; this is the backstop in case it
    /// hangs anyway. Any failure means the deterministic text is used.
    private func polish(
        _ request: PolishRequest, using configuration: PolishConfiguration?, progressive: ProgressivePolisher?
    ) async -> (PolishService.Outcome, PolishReport) {
        let service = PolishService(settings: settings)
        // The limit PolishService works to for this text, parts and all, so a long dictation's
        // polish isn't cut short here.
        let limit = Duration.seconds(service.overallTimeLimit(for: request, using: configuration) + Timing.polishGrace)
        do {
            return try await Watchdog.run(within: limit) {
                await service.polishLong(request, using: configuration, progressive: progressive)
            }
        } catch {
            var report = PolishReport()
            report.line.tag("fallback", error is CancellationError ? "cancelled" : "watchdog")
            return (PolishService.Outcome(text: request.text, provider: nil, note: "timed out"), report)
        }
    }

    /// Records whose saved audio a retry is reading right now; retention must leave it alone.
    private var retryingIDs: Set<UUID> = []

    private func applyAudioRetention() {
        // "Keep no audio": drop it the moment the dictation is settled. Failed records keep
        // theirs regardless — HistoryStore never purges those.
        if settings.audioRetentionDays == 0 {
            history.applyRetention(textDays: nil, audioDays: 0, sparing: retryingIDs)
        }
    }

    // MARK: - Phases

    private func fail(_ message: String, followUp: FollowUp? = nil) {
        Sounds.play(.error)
        showTransient(.failed(message), for: Timing.failedDisplay, followUp: followUp)
    }

    /// Where a blocked microphone sends the user: System Settings once access was refused.
    /// While it's undetermined the system's own prompt is the next step, so there's no link.
    private func blockedFollowUp() -> FollowUp? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: return .microphoneAccess
        default: return nil
        }
    }

    /// The microphone a recording would use: the chosen one if it's connected, else the
    /// system default. Plain HAL reads, cheap enough for the main thread.
    private func inputDeviceName() -> String? {
        AudioDevices.resolveInputDevice(uid: settings.inputDeviceUID).flatMap { AudioDevices.name(of: $0) }
    }

    /// Shows `phase` for `duration`, then returns to idle — unless something newer replaced it.
    private func showTransient(_ phase: Phase, for duration: Duration, followUp: FollowUp? = nil) {
        self.phase = phase
        self.followUp = followUp
        isFeedbackHeld = false
        isHandsFree = false
        level = 0
        levels = Self.silentLevels
        recordingStartedAt = nil
        scheduleReset(of: phase, after: duration)
    }

    private func scheduleReset(of phase: Phase, after duration: Duration) {
        phaseResetTask?.cancel()
        phaseResetTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled, self.phase == phase else { return }
            self.resetToIdle()
        }
    }

    private func resetToIdle() {
        phaseResetTask?.cancel()
        phaseResetTask = nil
        phase = .idle
        isHandsFree = false
        level = 0
        if levels != Self.silentLevels { levels = Self.silentLevels }
        recordingStartedAt = nil
        context = nil
        notice = nil
        followUp = nil
        isFeedbackHeld = false
    }

    // MARK: - Message pill

    /// The pointer is on (or has left) the HUD's clickable message. While it rests there the
    /// message stays; once it leaves, the message lingers briefly and goes.
    func holdFeedback(_ held: Bool) {
        guard followUp != nil else { return }
        switch phase {
        case .done, .failed: break
        default: return
        }
        guard held != isFeedbackHeld else { return }
        isFeedbackHeld = held
        if held {
            phaseResetTask?.cancel()
            phaseResetTask = nil
        } else {
            scheduleReset(of: phase, after: Timing.hoverLinger)
        }
    }

    /// The message was clicked: its follow-up is being taken, so the pill can go.
    func dismissFeedback() {
        switch phase {
        case .done, .failed: resetToIdle()
        default: break
        }
    }

    // MARK: - History actions

    /// Pastes the most recent dictation into the focused app again.
    func pasteLast() {
        guard let record = history.latestWithText ?? lastRecord, record.hasText else {
            NSSound.beep()
            return
        }
        Task { [weak self] in
            // ⌃⌥V is probably still held; a ⌘V posted now could reach the app as ⌃⌥⌘V.
            await Self.waitForModifiersReleased()
            self?.insert(record)
        }
    }

    /// Types a history item into the focused app.
    func insert(_ record: HistoryRecord) {
        guard record.hasText else { return }
        let text = record.finalText
        let restore = settings.restoreClipboard
        Task { [weak self] in
            await Self.yieldFocusIfNeeded()
            let outcome = await TextInjector.insert(text, restoreClipboard: restore)
            guard case .copied(let reason) = outcome else { return }
            Log.inject.info("insert from history copied instead: \(reason.message, privacy: .public)")
            // Say so the way a fresh dictation does, but never over a live one: a recording
            // or a result on screen belongs to that dictation, and the notice would leak into it.
            guard let self, self.phase == .idle, self.session == nil, self.processing == nil, !self.isStopping
            else { return }
            self.notice = reason.message
            self.showTransient(.done, for: Timing.copiedDisplay, followUp: reason.followUp)
        }
    }

    /// Re-runs speech recognition (and the text pipeline) on a record's saved audio. The result
    /// goes to the clipboard (outcome `.copied`) — typing into whatever is focused now would be
    /// a surprise.
    func retry(_ record: HistoryRecord) async {
        retryingIDs.insert(record.id)
        defer { retryingIDs.remove(record.id) }
        var updated = history.record(id: record.id) ?? record
        guard let url = history.audioURL(for: updated) else {
            updated.outcome = .failed
            updated.errorMessage = "The recording is no longer available"
            history.update(updated)
            return
        }

        let started = Date()
        var engineName = updated.engine
        let clock = ContinuousClock()
        var timing = TimingLine("retry \(record.id.uuidString.prefix(8))")
        timing.tag("engine", settings.engine.rawValue)
        defer {
            timing.ms("total", Self.milliseconds(since: started))
            timing.tag("outcome", updated.outcome.rawValue)
            Log.timing.notice("\(timing.text, privacy: .public)")
        }
        do {
            let readStart = clock.now
            let samples = try await Task.detached(priority: .userInitiated) {
                try AudioRecorder.readSamples(from: url)
            }.value
            timing.seconds("audio", Double(samples.count) / AudioRecorder.sampleRate)
            timing.ms("read", Self.milliseconds(readStart.duration(to: clock.now)))
            let context = updated.context ?? AppContext(bundleID: nil, appName: nil, category: .other)
            let style = updated.style ?? settings.style(for: context.category)
            let output = try await transcribeAndClean(
                samples, context: context, style: style, engineName: &engineName,
                live: nil, progressive: nil, purpose: .retry
            ) {}
            output.addStages(to: &timing)

            updated = history.record(id: record.id) ?? updated
            output.apply(to: &updated)
            updated.style = style
            updated.errorMessage = output.polishNote
            updated.timings.totalMs = Self.milliseconds(since: started)
            if output.result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.outcome = .empty
            } else {
                updated.outcome = .copied
                TextInjector.copy(output.result.text)
            }
            history.update(updated)
            if lastRecord?.id == updated.id { lastRecord = updated }
        } catch {
            updated = history.record(id: record.id) ?? updated
            updated.engine = engineName
            updated.outcome = .failed
            updated.errorMessage = error is CancellationError ? "Retry was cancelled" : message(for: error)
            history.update(updated)
        }
    }

    // MARK: - Helpers

    private struct DictationFailure: Error {
        let message: String
    }

    private func message(for error: Error) -> String {
        if let failure = error as? DictationFailure { return failure.message }
        if error is Watchdog.Expired { return "Transcription took too long" }
        // Its own limit comes before the watchdog's (`TranscriptionTimeLimit`), so this is
        // how a stuck Apple Speech usually ends.
        if let error = error as? AppleSpeechError {
            switch error {
            case .timedOut: return "Apple Speech stopped responding"
            }
        }
        if let error = error as? TranscriptionError {
            switch error {
            case .modelNotReady: return modelNotReadyMessage()
            case .audioUnreadable: return "The recording couldn't be read"
            default: return error.errorDescription ?? "Couldn't transcribe that"
            }
        }
        return "Couldn't transcribe that"
    }

    private func modelNotReadyMessage() -> String {
        if case .downloading = models.state { return "Speech model is still downloading" }
        if case .loading = models.state { return "Speech model is still loading" }
        if case .notDownloaded = models.state { return "Speech model not downloaded" }
        if case .failed = models.state { return "Speech model didn't load" }
        return "Speech model isn't ready yet"
    }

    private static func milliseconds(since date: Date) -> Int {
        Int((Date().timeIntervalSince(date) * 1000).rounded())
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    /// When the app itself is frontmost (a History button was clicked), step aside so the
    /// paste lands in the app the user was working in.
    private static func yieldFocusIfNeeded() async {
        guard NSApp.isActive else { return }
        NSApp.hide(nil)
        let me = ProcessInfo.processInfo.processIdentifier
        for _ in 0..<20 {
            if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func waitForModifiersReleased() async {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}

extension TextInjector.CopyReason {
    /// What the "copied" pill links to. Only a missing Accessibility grant has a fix to go to;
    /// otherwise the next step is ⌘V, and opening a window would take the paste target away.
    var followUp: DictationController.FollowUp? {
        switch self {
        case .noAccessibility: return .accessibilityAccess
        case .noTextField, .secureInput: return nil
        }
    }
}
