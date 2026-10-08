import AVFoundation
import AppKit
import Combine
import MurmurKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome
    case microphone
    case accessibility
    case model
    case shortcut
    case practice

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

/// First-run setup: welcome → microphone → accessibility → speech model → shortcut → try it.
///
/// The container owns all state and the footer, so the footer stays put while step content
/// slides; the steps themselves are presentational. Live facts come from the model, or from
/// `\.setupPreview` when rendering snapshots (which also suppresses every side effect).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.setupPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    @State private var step: OnboardingStep
    @State private var forward = true
    @State private var micDenied = false
    /// When the Try it step appeared. Only a dictation that started after this counts, so an
    /// earlier `lastRecord` (or one finishing from a previous step) can't fake a success.
    @State private var practiceStartedAt: Date?
    @State private var practiceDone = false
    /// The engine History recorded for the successful try ("Apple Speech" while Parakeet
    /// downloads).
    @State private var practiceEngine: String?
    /// Bumped whenever Birdtown Flow becomes active again, e.g. back from System Settings.
    @State private var activations = 0
    /// The permission step whose Open System Settings the user has clicked, so a step only says
    /// it's waiting for access once there's something to wait for (and opening the Microphone
    /// pane doesn't make the Accessibility step claim it too).
    @State private var settingsOpenedFor: OnboardingStep?

    private let onFinish: () -> Void

    init(initialStep: OnboardingStep = .welcome, onFinish: @escaping () -> Void = {}) {
        _step = State(initialValue: initialStep)
        self.onFinish = onFinish
    }

    // MARK: Live facts

    private var microphone: SetupPreview.Microphone {
        if let preview { return preview.microphone }
        if model.permissions.microphone { return .granted }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return micDenied || status == .denied || status == .restricted ? .denied : .notDetermined
    }

    private var accessibilityGranted: Bool { preview?.accessibility ?? model.permissions.accessibility }
    private var hotkeyActive: Bool { preview?.hotkeyActive ?? model.controller.isHotkeyActive }
    private var modelState: ModelManager.State { preview?.modelState ?? model.models.state }
    /// What transcribes while the selected model isn't ready (usually Apple Speech).
    private var standIn: String? {
        if let preview { return SetupKit.standIn(for: model.settings.engine, state: preview.modelState) }
        return model.models.standInName
    }
    /// The stand-in that wrote the successful try, if it wasn't the selected engine.
    private var practiceStandIn: String? {
        guard let engine = preview?.practiceEngine ?? practiceEngine,
              EngineFallback.ranOnStandIn(recordEngine: engine, selected: model.settings.engine.displayName)
        else { return nil }
        return engine
    }
    private var phase: DictationController.Phase { preview?.phase ?? model.controller.phase }
    private var practiceSucceeded: Bool { preview?.practiceSucceeded ?? practiceDone }
    private var needsRelaunch: Bool { accessibilityGranted && !hotkeyActive }
    private var canRelaunch: Bool { preview?.canRelaunch ?? SetupKit.canRelaunch }
    private var openedSettings: Bool { preview?.openedSettings ?? (settingsOpenedFor == step) }

    // System facts nothing observable tells us about: re-read each time the app comes back to
    // the front, since that's when the user has just changed them.
    private var fnHasSystemAction: Bool {
        _ = activations
        return preview?.fnHasSystemAction ?? SetupKit.fnKeyHasSystemAction
    }

    private var wisprRunning: Bool {
        _ = activations
        return preview?.wisprRunning ?? SetupKit.isWisprFlowRunning
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                content(for: step)
                    .id(step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if step != .welcome {
                footer.transition(.opacity)
            }
        }
        .frame(width: Layout.onboardingSize.width, height: Layout.onboardingSize.height)
        .background(Palette.canvas)
        .onAppear(perform: startWatching)
        .onDisappear {
            if preview == nil { model.permissions.stopPolling() }
        }
        .onChange(of: accessibilityGranted) { _, granted in accessibilityChanged(granted) }
        .onChange(of: hotkeyActive) { _, active in hotkeyChanged(active) }
        .onChange(of: model.controller.lastRecord?.id) { _, _ in checkPractice() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            activations += 1
        }
    }

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeStep(onStart: advance)
        case .microphone:
            MicrophoneStep(status: microphone, openedSettings: openedSettings)
                .padding(.bottom, Layout.Setup.footerHeight)
        case .accessibility:
            AccessibilityStep(
                granted: accessibilityGranted,
                needsRelaunch: needsRelaunch,
                canRelaunch: canRelaunch,
                openedSettings: openedSettings
            )
            .padding(.bottom, Layout.Setup.footerHeight)
        case .model:
            ModelStep(engine: model.settings.engine, state: modelState, standIn: standIn)
                .padding(.bottom, Layout.Setup.footerHeight)
                .onAppear(perform: prepareModel)
        case .shortcut:
            ShortcutStep(
                settings: model.settings,
                fnHasSystemAction: fnHasSystemAction,
                wisprRunning: wisprRunning,
                onChange: { model.controller.reloadShortcuts() },
                onRecording: { listening in
                    // The event tap would hear the keys being recorded first: pause it.
                    guard preview == nil else { return }
                    if listening {
                        model.controller.deactivate()
                    } else {
                        model.controller.activate()
                    }
                }
            )
            .padding(.bottom, Layout.Setup.footerHeight)
        case .practice:
            PracticeStep(
                key: model.settings.pushToTalkKey,
                phase: phase,
                hotkeyActive: hotkeyActive,
                microphoneGranted: microphone == .granted,
                engine: model.settings.engine,
                modelState: modelState,
                standIn: standIn,
                typedWith: practiceStandIn,
                succeeded: practiceSucceeded,
                initialText: preview?.practiceText,
                onFixAccessibility: { go(to: .accessibility) },
                onFixMicrophone: { go(to: .microphone) }
            )
            .padding(.bottom, Layout.Setup.footerHeight)
            .onAppear {
                if preview == nil { practiceStartedAt = Date() }
            }
        }
    }

    // MARK: Footer

    private struct FooterAction {
        let title: String
        let run: () -> Void
    }

    private var footer: some View {
        ZStack {
            ProgressDots(current: step)
            HStack(spacing: Spacing.s) {
                if let previous = step.previous {
                    Button("Back") { go(to: previous) }
                        .buttonStyle(SetupKit.QuietButtonStyle())
                }
                Spacer()
                if let secondary {
                    Button(secondary.title, action: secondary.run)
                        .buttonStyle(SetupKit.QuietButtonStyle())
                }
                Button(primary.title, action: primary.run)
                    .buttonStyle(SetupKit.PrimaryButtonStyle())
                    // Return belongs to the practice field until the try has worked, so
                    // pressing it there can't end setup early.
                    .keyboardShortcut(step != .practice || practiceSucceeded ? KeyboardShortcut.defaultAction : nil)
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(height: Layout.Setup.footerHeight)
    }

    private var primary: FooterAction {
        switch step {
        case .welcome:
            return FooterAction(title: "Get Started", run: advance)
        case .microphone:
            switch microphone {
            case .granted: return FooterAction(title: "Continue", run: advance)
            case .denied:
                return FooterAction(title: "Open System Settings") {
                    settingsOpenedFor = step
                    Permissions.openMicrophoneSettings()
                }
            case .notDetermined: return FooterAction(title: "Allow Microphone", run: requestMicrophone)
            }
        case .accessibility:
            if !accessibilityGranted {
                return FooterAction(title: "Open System Settings") {
                    // The prompt is what adds the app to the Accessibility list; opening the
                    // pane directly saves a click in the system alert.
                    settingsOpenedFor = step
                    Permissions.promptForAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
            if needsRelaunch && canRelaunch {
                return FooterAction(title: "Relaunch Birdtown Flow") { SetupKit.relaunch() }
            }
            return FooterAction(title: "Continue", run: advance)
        case .model where SetupKit.isFailed(modelState):
            return FooterAction(title: "Try Again", run: prepareModel)
        case .model, .shortcut:
            return FooterAction(title: "Continue", run: advance)
        case .practice:
            return FooterAction(title: practiceSucceeded ? "Start Using Birdtown Flow" : "Finish", run: finish)
        }
    }

    private var secondary: FooterAction? {
        switch step {
        case .microphone where microphone != .granted:
            return FooterAction(title: "Skip", run: advance)
        case .accessibility where !accessibilityGranted:
            return FooterAction(title: "Skip", run: advance)
        case .accessibility where needsRelaunch && canRelaunch:
            return FooterAction(title: "Later", run: advance)
        case .model where SetupKit.isFailed(modelState):
            return FooterAction(title: "Skip for Now", run: advance)
        default:
            return nil
        }
    }

    // MARK: Navigation

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let travel = forward ? Motion.stepTravel : -Motion.stepTravel
        return .asymmetric(
            insertion: .offset(x: travel).combined(with: .opacity),
            removal: .offset(x: -travel).combined(with: .opacity)
        )
    }

    private func advance() {
        if let next = step.next { go(to: next) }
    }

    private func go(to next: OnboardingStep) {
        guard next != step else { return }
        forward = next > step
        // The outgoing step reads `forward` for its exit transition; give it one update to
        // see the new direction before the step changes, so it leaves the right way.
        Task {
            withAnimation(Motion.resolve(Motion.gentle, reduceMotion: reduceMotion)) {
                step = next
            }
        }
    }

    private func finish() {
        guard preview == nil else { return }
        openWindow(id: "main")
        onFinish()
    }

    // MARK: Side effects (never in snapshots)

    private func startWatching() {
        guard preview == nil else { return }
        model.permissions.startPolling()
    }

    private func requestMicrophone() {
        guard preview == nil else { return }
        Task {
            let granted = await Permissions.requestMicrophone()
            model.permissions.refresh()
            micDenied = !granted
            guard granted else { return }
            // Let the check land before moving on.
            try? await Task.sleep(for: Motion.autoAdvanceDelay)
            if step == .microphone { go(to: .accessibility) }
        }
    }

    private func accessibilityChanged(_ granted: Bool) {
        guard preview == nil, granted else { return }
        // Arm the hotkey as soon as the tap can be created. If macOS still refuses (it
        // sometimes wants a fresh process after the grant), the step offers a relaunch.
        if !model.controller.isHotkeyActive {
            model.controller.activate()
        }
    }

    /// The step finishes when the hotkey is actually armed, not merely when access is granted:
    /// that covers an arm right after the grant and a late one from the controller's own
    /// retry loop, and it can only fire once per arming.
    private func hotkeyChanged(_ active: Bool) {
        guard preview == nil, active, step == .accessibility, accessibilityGranted else { return }
        Task {
            try? await Task.sleep(for: Motion.autoAdvanceDelay)
            if step == .accessibility { go(to: .model) }
        }
    }

    /// Starts (or joins) the model download. Unstructured on purpose: leaving the step must
    /// not cancel it — it keeps going in the background.
    private func prepareModel() {
        guard preview == nil else { return }
        Task { await model.models.prepare() }
    }

    private func checkPractice() {
        guard preview == nil, step == .practice, !practiceDone,
              let startedAt = practiceStartedAt,
              let record = model.controller.lastRecord,
              // `createdAt` is when that recording started.
              record.createdAt >= startedAt,
              record.outcome == .inserted || record.outcome == .copied,
              record.hasText
        else { return }
        practiceEngine = record.engine
        withAnimation(Motion.resolve(Motion.confirm, reduceMotion: reduceMotion)) {
            practiceDone = true
        }
    }
}

// MARK: - Progress

private struct ProgressDots: View {
    let current: OnboardingStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var steps: [OnboardingStep] { OnboardingStep.allCases.filter { $0 != .welcome } }

    var body: some View {
        HStack(spacing: Spacing.xs + Spacing.xxs) {
            ForEach(steps, id: \.self) { step in
                Capsule()
                    .fill(color(for: step))
                    .frame(
                        width: step == current ? Layout.Setup.progressDotActive : Layout.Setup.progressDot,
                        height: Layout.Setup.progressDot
                    )
            }
        }
        .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue) of \(steps.count)")
    }

    private func color(for step: OnboardingStep) -> Color {
        if step == current { return Palette.ink }
        return step < current ? Palette.inkTertiary : Palette.hairlineStrong
    }
}

// MARK: - Scaffold

/// The shared shape of a step: glyph, rounded title, a calm paragraph, then the step's controls.
private struct StepScaffold<Controls: View>: View {
    var symbol: String?
    var done = false
    let title: String
    let message: String
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.xxl)
            if let symbol {
                StepGlyph(symbol: symbol, done: done)
                    .padding(.bottom, Spacing.xl)
            }
            Text(title)
                .font(Typography.display)
                .tracking(Tracking.display)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            Text(message)
                .font(Typography.lead)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(Spacing.xxs)
                .frame(maxWidth: Layout.Setup.measure)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.s)
            controls
                .frame(maxWidth: Layout.Setup.controlsWidth)
                .padding(.top, Spacing.xxl)
            Spacer(minLength: Spacing.l)
        }
        .padding(.horizontal, Spacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The step's symbol in a soft disc. Turns into a green check when the step is done.
private struct StepGlyph: View {
    let symbol: String
    let done: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(done ? Palette.successSoft : Palette.surface)
            Circle().strokeBorder(done ? Palette.successSoft : Palette.hairline)
            Image(systemName: done ? "checkmark" : symbol)
                .font(Typography.stepGlyph)
                .fontWeight(done ? .semibold : .regular)
                .foregroundStyle(done ? Palette.success : Palette.ink)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? false : done)
        }
        .frame(width: Layout.Setup.stepGlyph, height: Layout.Setup.stepGlyph)
        .elevation(Elevation.card)
        .animation(Motion.resolve(Motion.confirm, reduceMotion: reduceMotion), value: done)
        .accessibilityHidden(true)
    }
}

// MARK: - 1 · Welcome

private struct WelcomeStep: View {
    let onStart: () -> Void
    @Environment(\.setupPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            SetupKit.AppMark(size: Layout.Setup.appIcon)
                .scaleEffect(appeared || reduceMotion ? 1 : Motion.pressedScale)
                // The product moment: the logo's own spectrum as light behind it, turning
                // slowly. A background, so it glows past the icon without moving the layout.
                .background { heroLight }
                .opacity(appeared ? 1 : 0)
            VStack(spacing: Spacing.xs) {
                Text("Birdtown Flow")
                    .font(Typography.hero)
                    .tracking(Tracking.display)
                    .foregroundStyle(Palette.ink)
                Text("Speak anywhere. It types for you.")
                    .font(Typography.title)
                    .fontWeight(.regular)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.top, Spacing.xxl)
            .offset(y: appeared || reduceMotion ? 0 : Spacing.s)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: Spacing.m) {
                Button("Get Started", action: onStart)
                    .buttonStyle(SetupKit.PrimaryButtonStyle(large: true))
                    .keyboardShortcut(.defaultAction)
                Text("Two permissions and a one-time download. You can dictate while it finishes.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.top, Spacing.huge)
            .opacity(appeared ? 1 : 0)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard preview == nil else {
                appeared = true
                return
            }
            withAnimation(Motion.resolve(Motion.gentle, reduceMotion: reduceMotion)) { appeared = true }
        }
    }

    /// Faint and soft, so the icon stays the hero: it should read as the icon's colours
    /// lighting the page, not as a second object. The orb fades out from the tile's edge to
    /// its rim; the tile hides its centre. No halo: it blooms on navy but smudges porcelain.
    private var heroLight: some View {
        SpectrumOrb(
            mode: .live,
            diameter: Layout.Setup.heroOrb,
            phase: preview == nil ? nil : Motion.snapshotOrbPhase
        )
        .mask {
            RadialGradient(
                colors: [.white, .clear],
                center: .center,
                startRadius: Layout.Setup.heroGlowInner,
                endRadius: Layout.Setup.heroOrb / 2
            )
        }
        .opacity(colorScheme == .dark ? Layout.Setup.heroOrbOpacityDark : Layout.Setup.heroOrbOpacityLight)
    }
}

// MARK: - 2 · Microphone

private struct MicrophoneStep: View {
    let status: SetupPreview.Microphone
    let openedSettings: Bool

    var body: some View {
        StepScaffold(
            symbol: "mic",
            done: status == .granted,
            title: "Let Birdtown Flow hear you",
            message: "Birdtown Flow only listens while you hold your shortcut. What you say becomes text right here on this Mac."
        ) {
            VStack(spacing: Spacing.m) {
                PermissionRow(symbol: "mic", title: "Microphone", state: rowState)
                if status == .denied {
                    SetupKit.Callout(
                        symbol: "exclamationmark.triangle.fill",
                        tint: Palette.warning,
                        fill: Palette.warningSoft,
                        text: "Microphone access is turned off. Turn on Birdtown Flow in Privacy & Security → Microphone, then come back."
                    )
                    if openedSettings {
                        WaitingForAccess()
                    }
                }
            }
        }
    }

    private var rowState: PermissionRow.Status {
        switch status {
        case .granted: .granted
        case .denied: .off
        case .notDetermined: .waiting("Not allowed yet")
        }
    }
}

/// One permission as a row: icon, name, and a status that lands on a check.
private struct PermissionRow: View {
    enum Status: Equatable {
        case waiting(String)
        case checking(String)
        case granted
        case off
    }

    let symbol: String
    let title: String
    let state: Status
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(Typography.bodyEmphasis)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: Layout.iconMedium)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.bodyEmphasis)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.m)
            badge
        }
        .setupCard(padding: Spacing.m + Spacing.xxs)
        .animation(Motion.resolve(Motion.confirm, reduceMotion: reduceMotion), value: state)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .waiting(let text):
            Text(text)
                .font(Typography.callout)
                .foregroundStyle(Palette.inkTertiary)
        case .checking(let text):
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text(text)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Palette.success)
                .transition(.scale.combined(with: .opacity))
        case .off:
            Label("Turned off", systemImage: "xmark.circle.fill")
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Palette.warning)
        }
    }
}

// MARK: - 3 · Accessibility

private struct AccessibilityStep: View {
    let granted: Bool
    let needsRelaunch: Bool
    let canRelaunch: Bool
    let openedSettings: Bool

    var body: some View {
        StepScaffold(
            symbol: "keyboard",
            done: granted && !needsRelaunch,
            title: "Let Birdtown Flow type for you",
            message: "Accessibility access lets Birdtown Flow notice your shortcut in any app, then type into the field you're using."
        ) {
            VStack(spacing: Spacing.m) {
                if granted {
                    // Allowed, but not working until the restart: say that, not a green check.
                    PermissionRow(
                        symbol: "accessibility",
                        title: "Accessibility",
                        state: needsRelaunch ? .waiting("Restart needed") : .granted
                    )
                } else {
                    instructions
                }
                if needsRelaunch {
                    SetupKit.Callout(
                        symbol: "arrow.clockwise",
                        tint: Palette.warning,
                        fill: Palette.warningSoft,
                        text: relaunchHint
                    )
                }
            }
        }
    }

    private var relaunchHint: String {
        if !canRelaunch {
            return "Access is on. Quit Birdtown Flow and open it again so macOS lets it hear your shortcut."
        }
        return "Access is on. macOS needs Birdtown Flow to restart once before it can hear your shortcut."
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            InstructionLine(number: 1, text: "Click Open System Settings below.")
            InstructionLine(number: 2, text: "Turn on Birdtown Flow in the Accessibility list.")
            InstructionLine(number: 3, text: "Come back here. This page updates by itself.")
            Divider().overlay(Palette.hairline)
            // A spinner only once there's something to wait for; before that it would
            // suggest the app is busy rather than waiting on the user.
            if openedSettings {
                WaitingForAccess()
            } else {
                Text("Not allowed yet")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .setupCard()
    }
}

/// Shown after the user has gone to System Settings: the page is watching and will update.
private struct WaitingForAccess: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            ProgressView().controlSize(.small)
            Text("Waiting for access…")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}

private struct InstructionLine: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text("\(number)")
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: Layout.iconMedium, height: Layout.iconMedium)
                .background(Circle().fill(Palette.sunken))
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
        }
    }
}

// MARK: - 4 · Speech model

private struct ModelStep: View {
    let engine: SpeechEngineChoice
    let state: ModelManager.State
    /// What transcribes until `engine` is ready; `nil` when it's ready or nothing can.
    let standIn: String?

    var body: some View {
        StepScaffold(
            symbol: "arrow.down",
            done: state == .ready,
            title: "Get the speech model",
            message: "Birdtown Flow turns speech into text on this Mac. The model downloads once, then works offline."
        ) {
            VStack(spacing: Spacing.m) {
                card
                if let note = carryOnNote {
                    Text(note)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var isPreparing: Bool {
        SetupKit.progress(of: state) != nil || state == .loading || state == .downloading(progress: nil)
    }

    /// Dictation doesn't wait for the download: say what does the work meanwhile, and that
    /// the switch is automatic.
    private var carryOnNote: String? {
        if let standIn, isPreparing {
            return "You can start dictating now. \(standIn) writes it down until \(engine.displayName) is ready, then Birdtown Flow switches by itself."
        }
        if let standIn, SetupKit.isFailed(state) {
            return "Dictation still works: \(standIn) writes it down until \(engine.displayName) is ready."
        }
        if isPreparing {
            return "You can carry on. You can try it as soon as the model is ready."
        }
        return nil
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "waveform")
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: Layout.iconMedium)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(engine.displayName)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                    Text("\(engine.downloadSize) · runs entirely on this Mac")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: Spacing.m)
                status
            }
            if let progress = SetupKit.progress(of: state) {
                SetupKit.ProgressBar(fraction: progress)
            }
            if case .failed(let message) = state {
                SetupKit.Callout(
                    symbol: "exclamationmark.triangle.fill",
                    tint: Palette.warning,
                    fill: Palette.warningSoft,
                    text: "The download stopped. Check your connection and try again."
                ) {
                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .setupCard()
    }

    @ViewBuilder
    private var status: some View {
        if state == .ready {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Palette.success)
        } else if let progress = SetupKit.progress(of: state) {
            Text(SetupKit.percent(progress))
                .font(Typography.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
        } else if state == .loading || state == .downloading(progress: nil) {
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text(SetupKit.describe(state))
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } else if !SetupKit.isFailed(state) {
            Text(SetupKit.describe(state))
                .font(Typography.callout)
                .foregroundStyle(Palette.inkTertiary)
        }
    }
}

// MARK: - 5 · Shortcut

private struct ShortcutStep: View {
    let settings: Settings
    let fnHasSystemAction: Bool
    let wisprRunning: Bool
    let onChange: () -> Void
    /// Pauses (`true`) and resumes Birdtown Flow's shortcuts while the recorder listens.
    var onRecording: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notice: ShortcutVerdict?

    private var key: PushToTalkKey { settings.pushToTalkKey }
    private var glyph: String { SetupKit.glyph(for: key) }
    private var keys: [String] { SetupKit.keys(for: key) }

    var body: some View {
        StepScaffold(
            title: "Choose your shortcut",
            message: "Hold it while you talk. Let go, and your words appear."
        ) {
            VStack(spacing: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    ForEach(SetupKit.orderedKeys, id: \.self) { option in
                        KeyOption(key: option, selected: option == key) { select(option) }
                    }
                }
                // One control to VoiceOver: "Push-to-talk key", a radio group with positions.
                .accessibilityRepresentation {
                    Picker("Push-to-talk key", selection: Binding(get: { key }, set: { select($0) })) {
                        ForEach(SetupKit.pickerKeys(including: key), id: \.self) { option in
                            Text(SetupKit.name(for: option)).tag(option)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                otherKey
                if let notice, notice != .accepted {
                    ShortcutNotice(verdict: notice)
                }
                gestures
                // Both can apply at once (Wispr Flow listens on fn by default), so neither
                // hides the other. Together they use shorter copy so the step still fits.
                if wisprRunning {
                    SetupKit.Callout(
                        symbol: "exclamationmark.triangle.fill",
                        tint: Palette.warning,
                        fill: Palette.warningSoft,
                        text: showsFnWarning
                            ? "Wispr Flow is running. Quit it, or pick another key."
                            : "Wispr Flow is running and may listen on the same key. Quit it, or pick a different key above."
                    )
                }
                if showsFnWarning {
                    SetupKit.Callout(
                        symbol: "globe",
                        tint: Palette.warning,
                        fill: Palette.warningSoft,
                        text: wisprRunning
                            ? "The 🌐 key also opens Emoji or Dictation. Set it to “Do Nothing”."
                            : "The 🌐 key also opens Emoji or Dictation. Set “Press 🌐 key to” to “Do Nothing” so only Birdtown Flow hears it."
                    ) {
                        Button("Open Keyboard Settings…", action: SetupKit.openKeyboardSettings)
                            .buttonStyle(SetupKit.InlineLinkStyle())
                    }
                }
            }
        }
    }

    private var showsFnWarning: Bool { key == .fn && fnHasSystemAction }

    /// Any other key or combination, through the recorder. Once one is chosen it shows here,
    /// selected, since none of the tiles above is.
    @ViewBuilder private var otherKey: some View {
        let recorder = ShortcutRecorder(
            role: .pushToTalk,
            look: .link(key.isQuickPick ? "Use a different key or combination…" : "Change…"),
            inUse: settings.shortcutsInUse,
            onListeningChange: onRecording,
            onVerdict: { notice = $0 },
            onRecord: { select($0) }
        )
        if key.isQuickPick {
            recorder
        } else {
            HStack(spacing: Spacing.s) {
                Text("Your shortcut")
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(Palette.ink)
                SetupKit.KeyCombo(keys: keys)
                recorder
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .background(Capsule(style: .continuous).fill(Palette.accentSoft))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.accent, lineWidth: Layout.Setup.selectionStroke))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Your shortcut: \(key.spokenName)")
        }
    }

    private func select(_ option: PushToTalkKey) {
        if option.isQuickPick { notice = nil }
        withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
            settings.pushToTalkKey = option
        }
        onChange()
    }

    private var gestures: some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .top, spacing: 0) {
                GestureHint(keys: keys, caption: "Hold to dictate")
                switch settings.handsFreeShortcut {
                case .doubleTap:
                    // A chord's keycaps twice over would crowd the row.
                    if keys.count == 1 {
                        GestureHint(keys: [glyph, glyph], caption: "Double-tap for hands-free")
                    } else {
                        GestureHint(keys: keys, caption: "Press twice for hands-free")
                    }
                case .controlOption:
                    GestureHint(
                        keys: SetupKit.handsFreeKeys(settings),
                        caption: settings.handsFreeChord == nil ? "Together for hands-free" : "Hands-free"
                    )
                case .off:
                    EmptyView()
                }
                GestureHint(keys: ["esc"], caption: "Cancel")
            }
            if settings.handsFreeShortcut == .controlOption {
                Text("Press \(SetupKit.handsFreeName(settings)) again to finish.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            } else if settings.handsFreeShortcut == .doubleTap {
                Text("Or hold \(SetupKit.name(for: key)) and press Space. Tap it again to finish.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(.vertical, Spacing.m - Spacing.xxs)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Palette.sunken))
    }

    private struct GestureHint: View {
        let keys: [String]
        let caption: String

        var body: some View {
            VStack(spacing: Spacing.s) {
                SetupKit.KeyCombo(keys: keys)
                Text(caption)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct KeyOption: View {
    let key: PushToTalkKey
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s) {
                SetupKit.KeyCap(label: SetupKit.glyph(for: key), large: true)
                Text(SetupKit.name(for: key))
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
            }
            .padding(.vertical, Spacing.s + Spacing.xxs)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .fill(selected ? Palette.accentSoft : (hovering ? Palette.surfaceHover : Palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .strokeBorder(
                        selected ? Palette.accent : Palette.hairline,
                        lineWidth: selected ? Layout.Setup.selectionStroke : Layout.Setup.hairline
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            // Keyboard focus in the card's own shape, outside the selection border, like the
            // provider and style cards.
            .flowFocusRing(RoundedRectangle(cornerRadius: Radius.l, style: .continuous), drawn: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { hovering = $0 }
        .accessibilityLabel(SetupKit.name(for: key))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 6 · Try it

private struct PracticeStep: View {
    let key: PushToTalkKey
    let phase: DictationController.Phase
    let hotkeyActive: Bool
    let microphoneGranted: Bool
    let engine: SpeechEngineChoice
    let modelState: ModelManager.State
    /// What transcribes until the selected model is ready (usually Apple Speech).
    let standIn: String?
    /// The stand-in that wrote the successful try, when it wasn't the selected engine.
    let typedWith: String?
    let succeeded: Bool
    let initialText: String?
    let onFixAccessibility: () -> Void
    let onFixMicrophone: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.setupPreview) private var preview

    /// Snapshots draw the orb at a fixed moment; live, it animates.
    private var orbPhase: Double? { preview == nil ? nil : Motion.snapshotOrbPhase }

    private var keyName: String { SetupKit.name(for: key) }

    var body: some View {
        StepScaffold(
            symbol: "waveform",
            done: succeeded,
            title: succeeded ? "That's it." : "Give it a try",
            message: succeeded
                ? "Birdtown Flow works like this in every app.\nHold \(keyName), speak, let go."
                : "Hold \(keyName) and say:"
        ) {
            VStack(spacing: Spacing.m) {
                if !succeeded {
                    Text("“Birdtown Flow is my new favourite way to write.”")
                        .font(Typography.transcriptLarge)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, Spacing.xs)
                }
                // The placeholder is drawn here rather than as the field's prompt: a vertical
                // macOS text field ignores the prompt's colour, and in full ink it reads as if
                // something had already been typed.
                TextField("Practice", text: $text, prompt: Text(""), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(Spacing.transcriptLine)
                    .lineLimit(3, reservesSpace: true)
                    .focused($focused)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Your words will appear here.")
                                .font(Typography.transcript)
                                .foregroundStyle(Palette.inkTertiary)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(Spacing.m)
                    .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Palette.sunken))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                            .strokeBorder(
                                focused ? Palette.accent : Palette.hairline,
                                lineWidth: focused ? Layout.Main.focusRing : Layout.Main.hairline
                            )
                    )
                status
            }
        }
        .onAppear {
            if let initialText { text = initialText }
            focused = true
        }
    }

    @ViewBuilder
    private var status: some View {
        if !hotkeyActive {
            HStack(spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                Text("Birdtown Flow can't hear your shortcut yet.")
                    .foregroundStyle(Palette.inkSecondary)
                Button("Fix Accessibility", action: onFixAccessibility)
                    .buttonStyle(SetupKit.InlineLinkStyle())
            }
            .font(Typography.callout)
        } else if !microphoneGranted {
            HStack(spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                Text("Birdtown Flow can't use the microphone yet.")
                    .foregroundStyle(Palette.inkSecondary)
                Button("Fix Microphone", action: onFixMicrophone)
                    .buttonStyle(SetupKit.InlineLinkStyle())
            }
            .font(Typography.callout)
        } else if phase.isRecording {
            HStack(spacing: Spacing.s) {
                SpectrumOrb(mode: .live, diameter: Layout.Orb.small, phase: orbPhase)
                Text("Listening… let go when you're done.")
                    .foregroundStyle(Palette.ink)
            }
            .font(Typography.callout)
        } else if phase.isBusy {
            HStack(spacing: Spacing.s) {
                SpectrumOrb(mode: .thinking, diameter: Layout.Orb.small, phase: orbPhase)
                Text("Writing it down…")
                    .foregroundStyle(Palette.inkSecondary)
            }
            .font(Typography.callout)
        } else if succeeded {
            VStack(spacing: Spacing.xs) {
                Label("Typed by Birdtown Flow", systemImage: "checkmark.circle.fill")
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(Palette.success)
                if let typedWith {
                    engineCaption(typedWithText(typedWith))
                }
            }
        } else if case .failed(let message) = phase {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                    .accessibilityHidden(true)
                Text(Self.retryHint(after: message))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Typography.callout)
        } else if standIn == nil, modelState == .loading || SetupKit.progress(of: modelState) != nil
                    || modelState == .downloading(progress: nil) {
            // Nothing can stand in (Apple Speech itself is getting ready): the try has to wait.
            VStack(spacing: Spacing.s) {
                if let progress = SetupKit.progress(of: modelState) {
                    SetupKit.ProgressBar(fraction: progress)
                }
                Text(modelWaitingText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(spacing: Spacing.xs) {
                Text("Waiting for you to hold \(keyName)…")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkTertiary)
                // The download doesn't hold the try up; just say which engine will hear it.
                if let note = SetupKit.standInNote(standIn, for: engine, state: modelState) {
                    engineCaption(note)
                }
            }
        }
    }

    /// A quiet line naming the engine: present, never the headline.
    private func engineCaption(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.inkTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
    }

    /// "Written with Apple Speech until Parakeet Ultra is ready", or, once it is, that the
    /// next dictation uses it.
    private func typedWithText(_ standIn: String) -> String {
        if modelState == .ready {
            return "Written with \(standIn). \(engine.displayName) is ready now and takes over from here."
        }
        let note = "Written with \(standIn) until \(engine.displayName) is ready"
        guard let progress = SetupKit.progress(of: modelState) else { return note }
        return "\(note) · \(SetupKit.percent(progress))"
    }

    /// The model isn't ready to hear the try yet; say so instead of waiting silently.
    private var modelWaitingText: String {
        if modelState == .loading {
            return "The speech model is getting ready. You can try as soon as it's ready."
        }
        if let progress = SetupKit.progress(of: modelState) {
            return "The speech model is still downloading · \(SetupKit.percent(progress)). You can try as soon as it's ready."
        }
        return "The speech model is still downloading. You can try as soon as it's ready."
    }

    /// "Speech model is still downloading. Try again."
    static func retryHint(after message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let ends = trimmed.last.map { ".!?…".contains($0) } ?? true
        return trimmed + (ends ? " Try again." : ". Try again.")
    }
}
