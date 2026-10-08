import AppKit
import Combine
import MurmurKit
import SwiftUI

// MARK: - General

struct GeneralSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.setupPreview) private var preview
    @State private var launchAtLogin = false
    @State private var launchNeedsApproval = false
    @State private var launchError: String?
    /// Why the last recorded shortcut was refused, or what to know about it, per row.
    @State private var shortcutNotices: [ShortcutRole: ShortcutVerdict]
    /// Snapshots only: draw this row's recorder as listening, with these keys held.
    private let previewRecording: (role: ShortcutRole, held: [String])?

    init(
        shortcutNotices: [ShortcutRole: ShortcutVerdict] = [:],
        previewRecording: (role: ShortcutRole, held: [String])? = nil
    ) {
        _shortcutNotices = State(initialValue: shortcutNotices)
        self.previewRecording = previewRecording
    }

    var body: some View {
        @Bindable var settings = model.settings
        SettingsPane {
            SettingsGroup(title: "Shortcuts") {
                SettingsRow(title: "Push-to-talk key", detail: "Hold to dictate, let go to type. Record any key you don't type with, or a combination.") {
                    HStack(spacing: Spacing.s) {
                        Picker("Push-to-talk key", selection: pushToTalkBinding) {
                            ForEach(SetupKit.pickerKeys(including: settings.pushToTalkKey), id: \.self) { key in
                                Text(SetupKit.name(for: key)).tag(key)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        recorder(.pushToTalk, look: .button("Record…")) { model.settings.pushToTalkKey = $0 }
                    }
                }
                notice(for: .pushToTalk)
                SettingsDivider()
                SettingsRow(title: "Hands-free", detail: handsFreeDetail(settings)) {
                    HStack(spacing: Spacing.s) {
                        Picker("Hands-free", selection: handsFreeBinding) {
                            Text(HandsFreeShortcut.doubleTap.title(keyName: SetupKit.name(for: settings.pushToTalkKey)))
                                .tag(HandsFreeChoice.doubleTap)
                            Text(HandsFreeShortcut.controlOption.title(keyName: "")).tag(HandsFreeChoice.controlOption)
                            if let chord = settings.handsFreeChord {
                                Text(chord.displayName).tag(HandsFreeChoice.recorded)
                            }
                            Text(HandsFreeShortcut.off.title(keyName: "")).tag(HandsFreeChoice.off)
                        }
                        .labelsHidden()
                        .fixedSize()
                        recorder(.handsFree, look: .button("Record…")) { shortcut in
                            guard let chord = shortcut.chord else { return }
                            model.settings.handsFreeChord = chord
                            model.settings.handsFreeShortcut = .controlOption
                        }
                    }
                }
                notice(for: .handsFree)
                SettingsDivider()
                SettingsRow(title: "Paste last dictation", detail: "Pastes what you said last into any app, again. Click the keys to change them.") {
                    HStack(spacing: Spacing.m) {
                        if settings.pasteLastShortcut != .pasteLastDefault {
                            IconButton(symbol: "arrow.uturn.backward", label: "Use \(KeyChord.pasteLastDefault.displayName) again") {
                                model.settings.pasteLastShortcut = .pasteLastDefault
                                shortcutNotices[.pasteLast] = nil
                            }
                        }
                        recorder(.pasteLast, look: .field, current: .keys(settings.pasteLastShortcut)) { shortcut in
                            guard let chord = shortcut.chord else { return }
                            model.settings.pasteLastShortcut = chord
                            model.settings.pasteLastShortcutEnabled = true
                        }
                        .opacity(settings.pasteLastShortcutEnabled ? 1 : Layout.Setup.disabledOpacity)
                        SettingsSwitch(label: "Paste last dictation", isOn: $settings.pasteLastShortcutEnabled)
                    }
                }
                notice(for: .pasteLast)
            }

            SettingsGroup(title: "Feedback") {
                SettingsRow(title: "Sounds", detail: "Soft cues when Birdtown Flow starts and stops listening.") {
                    SettingsSwitch(label: "Sounds", isOn: $settings.soundEnabled)
                }
                SettingsDivider()
                SettingsRow(title: "Resting pill", detail: "Keep a small pill at the bottom of the screen while Birdtown Flow is idle.") {
                    SettingsSwitch(label: "Resting pill", isOn: $settings.showIdlePill)
                }
            }

            SettingsGroup(title: "Appearance") {
                SettingsRow(title: "Light or dark", detail: "Follow your Mac, or always use one.") {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppearancePreference.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsGroup(title: "System") {
                SettingsRow(title: "Open at login", detail: launchDetail) {
                    HStack(spacing: Spacing.m) {
                        if launchNeedsApproval || launchError != nil {
                            Button("Open Login Items") {
                                guard preview == nil else { return }
                                LaunchAtLogin.openSystemSettings()
                            }
                            .buttonStyle(SetupKit.SecondaryButtonStyle())
                        }
                        SettingsSwitch(label: "Open at login", isOn: launchBinding)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Setup", detail: "Walk through permissions, the speech model and your shortcut again.") {
                    Button("Run Setup Again…") {
                        guard preview == nil else { return }
                        OnboardingWindowController.shared.show(model: model)
                    }
                    .buttonStyle(SetupKit.SecondaryButtonStyle())
                }
            }
        }
        .onAppear(perform: refreshLaunchAtLogin)
        // Approving (or removing) the login item happens in System Settings; pick it up on return.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
        .onChange(of: settings.pushToTalkKey) { reloadShortcuts() }
        .onChange(of: settings.handsFreeShortcut) { reloadShortcuts() }
        .onChange(of: settings.handsFreeChord) { reloadShortcuts() }
        .onChange(of: settings.pasteLastShortcutEnabled) { reloadShortcuts() }
        .onChange(of: settings.pasteLastShortcut) { reloadShortcuts() }
    }

    // MARK: Shortcuts

    /// The hands-free picker's choices: the recorded chord is its own row.
    private enum HandsFreeChoice: Hashable {
        case doubleTap, controlOption, recorded, off
    }

    /// Choosing from the picker clears a message left by the recorder beside it.
    private var pushToTalkBinding: Binding<PushToTalkKey> {
        Binding(
            get: { model.settings.pushToTalkKey },
            set: { key in
                model.settings.pushToTalkKey = key
                shortcutNotices[.pushToTalk] = nil
            }
        )
    }

    private var handsFreeBinding: Binding<HandsFreeChoice> {
        let settings = model.settings
        return Binding(
            get: { () -> HandsFreeChoice in
                switch settings.handsFreeShortcut {
                case .doubleTap: return .doubleTap
                case .controlOption: return settings.handsFreeChord == nil ? .controlOption : .recorded
                case .off: return .off
                }
            },
            set: { choice in
                shortcutNotices[.handsFree] = nil
                switch choice {
                case .doubleTap:
                    settings.handsFreeShortcut = .doubleTap
                case .controlOption:
                    // ⌃⌥ replaces a recorded chord; record again to get it back.
                    settings.handsFreeChord = nil
                    settings.handsFreeShortcut = .controlOption
                case .recorded:
                    settings.handsFreeShortcut = .controlOption
                case .off:
                    settings.handsFreeShortcut = .off
                }
            }
        )
    }

    private func recorder(
        _ role: ShortcutRole,
        look: ShortcutRecorder.Look,
        current: KeyShortcut? = nil,
        onRecord: @escaping (KeyShortcut) -> Void
    ) -> ShortcutRecorder {
        ShortcutRecorder(
            role: role,
            look: look,
            current: current,
            inUse: model.settings.shortcutsInUse,
            onListeningChange: pauseShortcuts,
            onVerdict: { verdict in
                if let verdict, verdict != .accepted {
                    shortcutNotices[role] = verdict
                } else {
                    shortcutNotices[role] = nil
                }
            },
            previewHeld: previewRecording?.role == role ? previewRecording?.held : nil,
            onRecord: onRecord
        )
    }

    @ViewBuilder private func notice(for role: ShortcutRole) -> some View {
        if let verdict = shortcutNotices[role], verdict != .accepted {
            ShortcutNotice(verdict: verdict)
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
        }
    }

    /// Birdtown Flow's own shortcuts would hear the keys being recorded first: pause them.
    private func pauseShortcuts(_ listening: Bool) {
        guard preview == nil else { return }
        if listening {
            model.controller.deactivate()
        } else {
            model.controller.activate()
        }
    }

    /// Names the keys the same way the picker beside it does.
    private func handsFreeDetail(_ settings: Settings) -> String {
        switch settings.handsFreeShortcut {
        case .doubleTap:
            return "Double-tap \(SetupKit.name(for: settings.pushToTalkKey)), or press Space while holding it, to keep listening. Tap again to finish."
        case .controlOption:
            if let chord = settings.handsFreeChord {
                return "Press \(chord.displayName) to keep listening without holding a key. Press it again to finish."
            }
            return "Press Control and Option together to keep listening without holding a key. Press them again to finish."
        case .off:
            return "Only hold to dictate."
        }
    }

    private var launchDetail: String {
        if launchNeedsApproval {
            return "Almost on: allow Birdtown Flow under System Settings → General → Login Items."
        }
        if let launchError { return launchError }
        return "Start Birdtown Flow quietly in the menu bar when you log in."
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                guard preview == nil else { return }
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                    launchError = nil
                } catch {
                    Log.app.error("login item change failed: \(error.localizedDescription, privacy: .public)")
                    launchError = enabled
                        ? "macOS didn't allow this. Turn Birdtown Flow on under System Settings → General → Login Items."
                        : "macOS didn't allow this. Turn Birdtown Flow off under System Settings → General → Login Items."
                }
                refreshLaunchAtLogin()
            }
        )
    }

    private func refreshLaunchAtLogin() {
        if let preview {
            launchAtLogin = preview.launchAtLogin
            return
        }
        launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
        launchNeedsApproval = LaunchAtLogin.needsApproval
        // Fixed in System Settings since the error: stop showing it.
        if LaunchAtLogin.isEnabled { launchError = nil }
    }

    private func reloadShortcuts() {
        guard preview == nil else { return }
        model.controller.reloadShortcuts()
    }
}

// MARK: - Audio & Speech

struct AudioSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.setupPreview) private var preview
    @State private var devices: [AudioInputDevice] = []
    @State private var pendingDelete: SpeechEngineChoice?
    // What's on disk isn't observable, and measuring it walks the model folders, so it's read
    // on appear and when something could have changed it — never on every progress tick.
    @State private var downloaded: Set<SpeechEngineChoice> = []
    @State private var deletable: Set<SpeechEngineChoice> = []
    @State private var diskUses: [SpeechEngineChoice: String] = [:]

    private var modelState: ModelManager.State { preview?.modelState ?? model.models.state }

    var body: some View {
        @Bindable var settings = model.settings
        SettingsPane {
            SettingsGroup(
                title: "Microphone",
                footnote: "Tip: your Mac's built-in microphone avoids the low-quality call mode AirPods switch to while they record."
            ) {
                SettingsRow(title: "Input", detail: "The microphone Birdtown Flow listens to.") {
                    Picker("Input", selection: $settings.inputDeviceUID) {
                        Text("System default").tag(String?.none)
                        if let uid = settings.inputDeviceUID, !devices.contains(where: { $0.uid == uid }) {
                            Text("Unavailable microphone").tag(String?.some(uid))
                        }
                        ForEach(devices) { device in
                            Text(device.name).tag(String?.some(device.uid))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: "Lower other audio", detail: "Quiets music and video while you dictate.") {
                    SettingsSwitch(label: "Lower other audio", isOn: $settings.duckAudioWhileRecording)
                }
            }

            SettingsGroup(title: "Speech engine") {
                ForEach(SpeechEngineChoice.allCases) { choice in
                    if choice != SpeechEngineChoice.allCases.first {
                        SettingsDivider()
                    }
                    EngineRow(
                        choice: choice,
                        selected: settings.engine == choice,
                        downloaded: downloaded.contains(choice),
                        deletable: deletable.contains(choice),
                        diskUse: diskUses[choice],
                        state: modelState,
                        onUse: { use(choice) },
                        onDelete: { pendingDelete = choice }
                    )
                }
            }

            SettingsGroup(title: "Recognition") {
                SettingsRow(
                    title: "Boost dictionary words",
                    detail: "Helps the engine catch names and jargon from your Dictionary."
                ) {
                    SettingsSwitch(label: "Boost dictionary words", isOn: $settings.vocabularyBoosting)
                }
            }
        }
        .onAppear {
            devices = preview?.devices ?? AudioDevices.inputDevices()
            refreshDisk()
        }
        .onChange(of: settings.engine) { refreshDisk() }
        .onChange(of: stateKind) { refreshDisk() }
        .confirmationDialog(
            "Delete this speech model?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { choice in
            Button("Delete \(choice.displayName)", role: .destructive) {
                guard preview == nil else { return }
                model.models.deleteModel(choice)
                refreshDisk()
            }
        } message: { choice in
            Text("Frees \(diskUses[choice] ?? choice.downloadSize) of disk space. You can download it again any time.")
        }
    }

    /// The model's broad state, without download progress, so disk facts refresh when a
    /// download starts, finishes or fails rather than on every percent.
    private var stateKind: Int {
        if SetupKit.progress(of: modelState) != nil || modelState == .downloading(progress: nil) { return 1 }
        if modelState == .loading { return 2 }
        if modelState == .ready { return 3 }
        if SetupKit.isFailed(modelState) { return 4 }
        return 0
    }

    private func refreshDisk() {
        if let preview {
            downloaded = preview.downloaded
            deletable = preview.downloaded.filter { $0.isParakeet && $0 != model.settings.engine }
            return
        }
        let models = model.models
        let all = SpeechEngineChoice.allCases
        downloaded = Set(all.filter { models.isDownloaded($0) })
        // Mirrors `ModelManager.canDelete`: never the selected engine; partial downloads count.
        deletable = Set(all.filter { models.canDelete($0) })
        diskUses = all.reduce(into: [:]) { sizes, choice in
            if let bytes = models.diskSize(of: choice) {
                sizes[choice] = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
        }
    }

    /// Picking an engine is all it takes: ModelManager follows the setting, preparing the new
    /// engine (downloading if needed) while the previous one keeps serving dictations. Only a
    /// retry of the engine already selected needs an explicit `prepare()`, unstructured so
    /// closing Settings doesn't cancel it.
    private func use(_ choice: SpeechEngineChoice) {
        guard preview == nil else { return }
        if model.settings.engine == choice {
            Task { await model.models.prepare() }
        } else {
            model.settings.engine = choice
        }
    }
}

private struct EngineRow: View {
    let choice: SpeechEngineChoice
    let selected: Bool
    let downloaded: Bool
    let deletable: Bool
    /// Space the model takes on disk now, when there's anything there.
    let diskUse: String?
    let state: ModelManager.State
    let onUse: () -> Void
    let onDelete: () -> Void

    private var detail: String {
        // Apple Speech's size line ("Managed by macOS") just repeats its detail.
        guard choice.isParakeet else { return choice.detail }
        guard downloaded else { return "\(choice.detail) \(choice.downloadSize) download." }
        if let diskUse { return "\(choice.detail) Uses \(diskUse)." }
        return "\(choice.detail) Downloaded."
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            // A mark, not a control: the trailing Use and Download buttons switch engines.
            // Always laid out so the names line up; shown only on the selected engine.
            Image(systemName: "checkmark")
                .font(Typography.bodyEmphasis)
                .foregroundStyle(Palette.accent)
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.s) {
                    Text(choice.displayName)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                    if choice == .parakeetUltra {
                        Badge(text: "Recommended", tone: .neutral)
                    }
                }
                Text(detail)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if selected, let progress = SetupKit.progress(of: state) {
                    SetupKit.ProgressBar(fraction: progress)
                        .padding(.top, Spacing.xs)
                }
                if selected, case .failed(let message) = state {
                    Text(message)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var trailing: some View {
        if selected {
            if state == .ready {
                Label("In use", systemImage: "checkmark.circle.fill")
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(Palette.success)
            } else if let progress = SetupKit.progress(of: state) {
                Text(SetupKit.percent(progress))
                    .font(Typography.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
            } else if state == .loading || state == .downloading(progress: nil) {
                ProgressView().controlSize(.small)
            } else {
                Button(SetupKit.isFailed(state) ? "Try Again" : "Download", action: onUse)
                    .buttonStyle(SetupKit.SecondaryButtonStyle())
            }
        } else if downloaded || !choice.isParakeet {
            HStack(spacing: Spacing.s) {
                if deletable {
                    IconButton(symbol: "trash", label: "Delete the downloaded \(choice.displayName) model", action: onDelete)
                }
                Button("Use", action: onUse)
                    .buttonStyle(SetupKit.SecondaryButtonStyle())
                    .help("Switch to \(choice.displayName)")
            }
        } else {
            HStack(spacing: Spacing.s) {
                // A partial download can still be cleared away.
                if deletable {
                    IconButton(symbol: "trash", label: "Delete the partial \(choice.displayName) download", action: onDelete)
                }
                Button("Download", action: onUse)
                    .buttonStyle(SetupKit.SecondaryButtonStyle())
                    .help("Switch to \(choice.displayName) and download it. Dictation keeps working meanwhile.")
            }
        }
    }
}

// MARK: - Text & AI

struct TextSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.setupPreview) private var preview
    @Environment(\.openWindow) private var openWindow
    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var testing = false
    @State private var testResult: Result<String, any Error>?
    /// Where Claude Code was found; `nil` until looked up or when it isn't installed.
    @State private var claudeCodePath: String?
    @State private var claudeCodeChecked = false
    /// Set when a provider card is clicked, so its settings scroll into view once they show.
    @State private var revealProviderSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let providerSettingsID = "providerSettings"

    var body: some View {
        @Bindable var settings = model.settings
        ScrollViewReader { proxy in
            pane(settings, proxy: proxy)
        }
        .onAppear(perform: refreshKey)
        .onChange(of: settings.polishProvider) { polishSettingsChanged() }
        .onChange(of: settings.polishLevel) { polishSettingsChanged() }
        .task(id: settings.polishProvider) {
            guard settings.polishProvider == .claudeCode else { return }
            if let preview {
                claudeCodePath = preview.keySaved ? "~/.local/bin/claude" : nil
                claudeCodeChecked = true
                return
            }
            claudeCodePath = await ClaudeCodeSessions.shared.installedPath()
            claudeCodeChecked = true
        }
    }

    /// Picking a provider reveals its settings (the API key first of all) below the cards,
    /// often below the fold: bring them into view so the click visibly did something.
    private func revealProviderSettingsIfNeeded(_ proxy: ScrollViewProxy) {
        guard revealProviderSettings else { return }
        revealProviderSettings = false
        withAnimation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion)) {
            proxy.scrollTo(Self.providerSettingsID, anchor: .top)
        }
    }

    private func pane(_ source: Settings, proxy: ScrollViewProxy) -> some View {
        @Bindable var settings = source
        return SettingsPane {
            SettingsGroup(title: "Basics", footnote: "These run on every dictation, with or without AI polish.") {
                SettingsRow(title: "Remove filler words", detail: "Drops “um”, “uh” and false starts.") {
                    SettingsSwitch(label: "Remove filler words", isOn: $settings.removeFillers)
                }
                SettingsDivider()
                SettingsRow(title: "Spoken commands", detail: "Say “new line” or “new paragraph” to break the text.") {
                    SettingsSwitch(label: "Spoken commands", isOn: $settings.spokenCommands)
                }
                SettingsDivider()
                SettingsRow(title: "Restore clipboard", detail: "Puts back what was on your clipboard after Birdtown Flow pastes.") {
                    SettingsSwitch(label: "Restore clipboard", isOn: $settings.restoreClipboard)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("AI polish")
                    .eyebrowStyle()
                    .padding(.leading, Spacing.xs)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)],
                    spacing: Spacing.m
                ) {
                    ForEach(PolishProvider.allCases) { provider in
                        ProviderCard(provider: provider, selected: settings.polishProvider == provider) {
                            revealProviderSettings = provider != .off && provider != settings.polishProvider
                            settings.polishProvider = provider
                            testResult = nil
                            refreshKey()
                        }
                    }
                }
            }

            if settings.polishProvider != .off {
                providerSettings(settings)
                    .id(Self.providerSettingsID)
                    // From Off the group appears; between providers it changes in place.
                    .onAppear { revealProviderSettingsIfNeeded(proxy) }
                    .onChange(of: settings.polishProvider) { revealProviderSettingsIfNeeded(proxy) }
            }

            labGroup
        }
    }

    private func polishSettingsChanged() {
        guard preview == nil else { return }
        model.controller.polishSettingsChanged()
    }

    /// Which styles the Lab has taken over, and the way there.
    private var labGroup: some View {
        let lab = model.lab
        let styles = lab.assignedStyles
        let detail = styles.isEmpty
            ? "Not used by any style yet. Try other instructions and models on real dictations."
            : "Used by \(ListFormatter.localizedString(byJoining: styles.map(\.title)))."
                + (model.settings.polishProvider == .off
                    ? " Turn AI polish on for them to take effect."
                    : " Other styles use the settings above.")
        return SettingsGroup(title: "Lab") {
            SettingsRow(title: "Prompt Lab", detail: detail) {
                Button("Open Lab") {
                    guard preview == nil else { return }
                    openWindow(id: "main")
                    model.show(.lab)
                }
                .buttonStyle(SetupKit.SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func providerSettings(_ source: Settings) -> some View {
        @Bindable var settings = source
        let provider = source.polishProvider
        let availability: (available: Bool, reason: String?) =
            preview == nil ? PolishService(settings: source).availability() : (available: true, reason: nil)
        VStack(alignment: .leading, spacing: Spacing.m) {
            if !availability.available, let reason = availability.reason {
                SetupKit.Callout(
                    symbol: "exclamationmark.triangle.fill",
                    tint: Palette.warning,
                    fill: Palette.warningSoft,
                    text: reason
                )
            }
            SettingsGroup(title: provider.title) {
                SettingsRow(title: "How much to edit", detail: settings.polishLevel.detail) {
                    Picker("How much to edit", selection: $settings.polishLevel) {
                        ForEach(PolishLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                if provider == .claudeCode {
                    SettingsRow(
                        title: "Claude Code",
                        detail: "Claude Haiku 5.5 at low effort, through Claude Code signed in on this Mac, on your Claude plan. For personal testing: it comes out before Birdtown Flow is sold."
                    ) {
                        claudeCodeStatus
                    }
                    SettingsDivider()
                }
                if provider.isCloud {
                    SettingsRow(title: "API key", detail: keySaved ? "Stored in your Keychain, never shown again." : "Saved to your Keychain, not to disk.") {
                        apiKeyControl(provider)
                    }
                    SettingsDivider()
                }
                if provider == .anthropic {
                    SettingsRow(title: "Model") {
                        TextField("Model", text: $settings.anthropicModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: Layout.sidebarWidth)
                    }
                    SettingsDivider()
                }
                if provider == .openAICompatible {
                    SettingsRow(title: "Base URL", detail: "OpenAI, Groq, Ollama, LM Studio…") {
                        TextField("Base URL", text: $settings.openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: Layout.sidebarWidth)
                    }
                    SettingsDivider()
                    SettingsRow(title: "Model") {
                        TextField("Model", text: $settings.openAIModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: Layout.sidebarWidth)
                    }
                    SettingsDivider()
                }
                SettingsRow(title: "Time limit", detail: "If polish takes longer, Birdtown Flow types the plain transcript.") {
                    Stepper(value: $settings.polishTimeout, in: 1...15, step: 1) {
                        Text("\(Int(settings.polishTimeout)) s")
                            .font(Typography.body)
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                    }
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: "Test", detail: "Polishes a sample sentence with these settings.") {
                    Button {
                        runTest()
                    } label: {
                        if testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Test")
                        }
                    }
                    .buttonStyle(SetupKit.SecondaryButtonStyle())
                    .disabled(testing)
                }
                if let testResult {
                    testOutcome(testResult)
                        .padding(.horizontal, Spacing.l)
                        .padding(.bottom, Spacing.m)
                }
            }
        }
    }

    @ViewBuilder
    private var claudeCodeStatus: some View {
        if !claudeCodeChecked {
            ProgressView().controlSize(.small)
        } else if claudeCodePath != nil {
            Label("Found", systemImage: "checkmark.circle.fill")
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Palette.success)
                .help(claudeCodePath ?? "")
        } else {
            Label("Not installed", systemImage: "exclamationmark.triangle.fill")
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Palette.warning)
        }
    }

    @ViewBuilder
    private func apiKeyControl(_ provider: PolishProvider) -> some View {
        if keySaved {
            HStack(spacing: Spacing.m) {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(Palette.success)
                Button("Remove") {
                    guard preview == nil else { return }
                    Keychain.set(nil, for: account(for: provider))
                    refreshKey()
                }
                .buttonStyle(SetupKit.SecondaryButtonStyle())
            }
        } else {
            HStack(spacing: Spacing.s) {
                SecureField("API key", text: $keyDraft, prompt: Text("Paste your key"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Layout.sidebarWidth - Spacing.huge)
                    .onSubmit { saveKey(provider) }
                Button("Save") { saveKey(provider) }
                    .buttonStyle(SetupKit.SecondaryButtonStyle())
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func testOutcome(_ result: Result<String, any Error>) -> some View {
        switch result {
        case .success(let text):
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("It works", systemImage: "checkmark.circle.fill")
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(Palette.success)
                Text(text)
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.m)
                    .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(Palette.sunken))
            }
        case .failure(let error):
            SetupKit.Callout(
                symbol: "xmark.octagon.fill",
                tint: Palette.danger,
                fill: Palette.dangerSoft,
                text: error.localizedDescription
            )
        }
    }

    private func account(for provider: PolishProvider) -> Keychain.Account {
        provider == .anthropic ? .anthropic : .openAICompatible
    }

    private func refreshKey() {
        if let preview {
            keySaved = preview.keySaved
            return
        }
        let provider = model.settings.polishProvider
        guard provider.isCloud else {
            keySaved = false
            return
        }
        keySaved = !(Keychain.string(for: account(for: provider)) ?? "").isEmpty
        keyDraft = ""
    }

    private func saveKey(_ provider: PolishProvider) {
        guard preview == nil else { return }
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Keychain.set(key, for: account(for: provider))
        // Never keep the key in view state longer than needed.
        keyDraft = ""
        refreshKey()
        testResult = nil
    }

    private func runTest() {
        guard preview == nil else { return }
        testing = true
        testResult = nil
        Task {
            let result = await PolishService(settings: model.settings).test()
            testResult = result
            testing = false
        }
    }
}

private struct ProviderCard: View {
    let provider: PolishProvider
    let selected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    private var locality: (text: String, symbol: String) {
        if provider == .off { return ("Nothing leaves this Mac", "lock") }
        if provider == .anthropic || provider == .claudeCode { return ("Text is sent to Anthropic", "cloud") }
        if provider.isCloud { return ("Text is sent to the endpoint you set", "cloud") }
        return ("Runs on this Mac", "desktopcomputer")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(provider.title)
                        .font(Typography.headline)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: Spacing.s)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Palette.accent : Palette.inkTertiary)
                        .accessibilityHidden(true)
                }
                Text(provider.subtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                Label(locality.text, systemImage: locality.symbol)
                    .font(Typography.caption)
                    .foregroundStyle(provider.isCloud ? Palette.inkSecondary : Palette.inkTertiary)
                    .padding(.top, Spacing.xxs)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ProviderCardButtonStyle(selected: selected, drawsFocusRing: isFocused))
        // The style draws a Signal blue focus ring outside the card, clear of its selection border.
        .focusEffectDisabled()
        .focused($isFocused)
        .accessibilityLabel("\(provider.title). \(provider.subtitle) \(locality.text).")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A provider card's surface: selected, hovered and pressed fills, the selection border, and
/// a Signal blue focus ring under keyboard focus. Pass the button's own focus as
/// `drawsFocusRing` and put `.focusEffectDisabled()` on the button.
private struct ProviderCardButtonStyle: ButtonStyle {
    let selected: Bool
    var drawsFocusRing = false

    func makeBody(configuration: Configuration) -> some View {
        ProviderCardButtonBody(configuration: configuration, selected: selected, drawsFocusRing: drawsFocusRing)
    }
}

private struct ProviderCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let drawsFocusRing: Bool

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        configuration.label
            .background(shape.fill(fill))
            .overlay(
                shape.strokeBorder(
                    selected ? Palette.accent : Palette.hairline,
                    lineWidth: selected ? Layout.Setup.selectionStroke : Layout.Setup.hairline
                )
            )
            .contentShape(shape)
            .flowFocusRing(shape, drawn: drawsFocusRing)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Interaction.pressedScale : 1)
            .onHover { hovering = $0 }
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: hovering)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var fill: Color {
        if selected { return Palette.accentSoft }
        if configuration.isPressed { return Palette.surfacePressed }
        return hovering ? Palette.surfaceHover : Palette.surface
    }
}

// MARK: - Privacy & History

struct PrivacySettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.setupPreview) private var preview
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = model.settings
        SettingsPane {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "lock.shield")
                    .font(Typography.title)
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Your voice stays on this Mac")
                        .font(Typography.headline)
                        .foregroundStyle(Palette.ink)
                    Text("Audio and text never leave this Mac unless you choose a cloud polisher in Text & AI. Then only the text of each dictation is sent, to the provider you picked.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Palette.sunken))

            SettingsGroup(title: "History", footnote: "Older dictations are removed automatically.") {
                SettingsRow(title: "Keep history", detail: "Text of every dictation, searchable in History.") {
                    Picker("Keep history", selection: $settings.historyRetentionDays) {
                        // Shortest first, like Keep audio below.
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Divider()
                        Text("Forever").tag(0)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: "Keep audio", detail: "Recordings let you replay or retry a dictation.") {
                    Picker("Keep audio", selection: $settings.audioRetentionDays) {
                        Text("Don't keep").tag(0)
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Divider()
                        Text("Forever").tag(-1)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsGroup(title: "Data") {
                SettingsRow(title: "Data folder", detail: "History, recordings, dictionary and snippets.") {
                    Button("Show in Finder") {
                        guard preview == nil else { return }
                        _ = NSWorkspace.shared.open(AppPaths.support)
                    }
                    .buttonStyle(SetupKit.SecondaryButtonStyle())
                }
                SettingsDivider()
                SettingsRow(title: "Clear history", detail: "Removes every dictation and its audio from this Mac.") {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .buttonStyle(.flowSecondary)
                        .disabled(model.history.records.isEmpty)
                }
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) {
                guard preview == nil else { return }
                model.history.deleteAll()
            }
        } message: {
            Text("Every dictation and recording will be deleted. This can't be undone.")
        }
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    private struct Credit: Identifiable {
        let title: String
        let detail: String
        let link: String
        var id: String { title }
    }

    private let credits = [
        Credit(title: "Parakeet", detail: "Speech recognition models by NVIDIA.", link: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3"),
        Credit(title: "Parakeet Ultra", detail: "Post-trained for accuracy by moondream.", link: "https://moondream.ai"),
        Credit(title: "FluidAudio", detail: "Runs Parakeet on the Neural Engine with Core ML.", link: "https://github.com/FluidInference/FluidAudio"),
        Credit(title: "murmur-youtube", detail: "The open-source project Birdtown Flow grew from.", link: "https://github.com/per-simmons/murmur-youtube"),
    ]

    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        if let build = info?["CFBundleVersion"] as? String, build != short {
            return "Version \(short) (\(build))"
        }
        return "Version \(short)"
    }

    var body: some View {
        SettingsPane {
            VStack(spacing: Spacing.s) {
                SetupKit.AppMark(size: Layout.Setup.aboutIcon)
                    .padding(.bottom, Spacing.s)
                Text("Birdtown Flow")
                    .font(Typography.display)
                    .tracking(Tracking.display)
                    .foregroundStyle(Palette.ink)
                Text("Speak anywhere. It types for you.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkSecondary)
                Text(version)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkTertiary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)

            SettingsGroup(title: "Built with") {
                ForEach(credits) { credit in
                    if credit.id != credits.first?.id {
                        SettingsDivider()
                    }
                    SettingsRow(title: credit.title, detail: credit.detail) {
                        if let url = URL(string: credit.link) {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(Palette.accent)
                            }
                            .help(credit.link)
                            .accessibilityLabel("Open \(credit.title) website")
                        }
                    }
                }
            }
        }
    }
}
