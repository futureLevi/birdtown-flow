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

    var body: some View {
        @Bindable var settings = model.settings
        SettingsPane {
            SettingsGroup(title: "Shortcuts") {
                SettingsRow(title: "Push-to-talk key", detail: "Hold to talk, let go to type.") {
                    Picker("Push-to-talk key", selection: $settings.pushToTalkKey) {
                        ForEach(SetupKit.orderedKeys, id: \.self) { key in
                            Text(SetupKit.name(for: key)).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(
                    title: "Hands-free",
                    detail: "Double-tap the key, or press Space while holding it, to keep listening. Tap again to finish."
                ) {
                    SettingsSwitch(label: "Hands-free", isOn: $settings.handsFreeEnabled)
                }
                SettingsDivider()
                SettingsRow(title: "Paste last dictation", detail: "Pastes what you said last into any app, again.") {
                    HStack(spacing: Spacing.m) {
                        SetupKit.KeyCombo(keys: ["⌃", "⌥", "V"])
                            .opacity(settings.pasteLastShortcutEnabled ? 1 : Layout.Setup.disabledOpacity)
                        SettingsSwitch(label: "Paste last dictation", isOn: $settings.pasteLastShortcutEnabled)
                    }
                }
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
                SettingsDivider()
                SettingsRow(
                    title: "Title font",
                    detail: "Page titles, big numbers and the welcome screen. Everything you read stays SF Pro."
                ) {
                    Picker("Title font", selection: $settings.typeTreatment) {
                        ForEach(TypeTreatment.allCases) { treatment in
                            Text(treatment.displayName).tag(treatment)
                        }
                    }
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
        .onChange(of: settings.handsFreeEnabled) { reloadShortcuts() }
        .onChange(of: settings.pasteLastShortcutEnabled) { reloadShortcuts() }
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
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(Typography.body)
                .foregroundStyle(selected ? Palette.accent : Palette.inkTertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.s) {
                    Text(choice.displayName)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                    if choice == .parakeetUltra {
                        Text("Recommended")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, Spacing.xxs)
                            .background(Capsule().fill(Palette.sunken))
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
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete the downloaded \(choice.displayName) model")
                    .accessibilityLabel("Delete \(choice.displayName)")
                }
                Button("Use", action: onUse)
                    .buttonStyle(SetupKit.SecondaryButtonStyle())
                    .help("Switch to \(choice.displayName)")
            }
        } else {
            HStack(spacing: Spacing.s) {
                // A partial download can still be cleared away.
                if deletable {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete the partial \(choice.displayName) download")
                    .accessibilityLabel("Delete partial \(choice.displayName) download")
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
    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var testing = false
    @State private var testResult: Result<String, any Error>?

    var body: some View {
        @Bindable var settings = model.settings
        SettingsPane {
            SettingsGroup(title: "Cleanup") {
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
                            settings.polishProvider = provider
                            testResult = nil
                            refreshKey()
                        }
                    }
                }
            }

            if settings.polishProvider != .off {
                providerSettings(settings)
            }
        }
        .onAppear(perform: refreshKey)
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
    @State private var hovering = false

    private var locality: (text: String, symbol: String) {
        if provider == .off { return ("Nothing leaves this Mac", "lock") }
        if provider == .anthropic { return ("Text is sent to Anthropic", "cloud") }
        if provider.isCloud { return ("Text is sent to the endpoint you set", "cloud") }
        return ("Runs on this Mac", "desktopcomputer")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
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
            .background(shape.fill(selected ? Palette.accentSoft : (hovering ? Palette.surfaceHover : Palette.surface)))
            .overlay(
                shape.strokeBorder(
                    selected ? Palette.accent : Palette.hairline,
                    lineWidth: selected ? Layout.Setup.selectionStroke : Layout.Setup.hairline
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(provider.title). \(provider.subtitle) \(locality.text).")
        .accessibilityAddTraits(selected ? .isSelected : [])
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

            SettingsGroup(title: "History", footnote: "Older dictations are removed automatically when Birdtown Flow starts.") {
                SettingsRow(title: "Keep history", detail: "Text of every dictation, searchable in History.") {
                    Picker("Keep history", selection: $settings.historyRetentionDays) {
                        Text("Forever").tag(0)
                        Text("90 days").tag(90)
                        Text("30 days").tag(30)
                        Text("7 days").tag(7)
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
                        .buttonStyle(SetupKit.SecondaryButtonStyle())
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
