import AVFoundation
import AppKit
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
    @State private var relaunchFailed = false
    @State private var practiceBaseline: UUID?
    @State private var practiceDone = false

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
    private var phase: DictationController.Phase { preview?.phase ?? model.controller.phase }
    private var practiceSucceeded: Bool { preview?.practiceSucceeded ?? practiceDone }
    private var needsRelaunch: Bool { accessibilityGranted && !hotkeyActive }

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
        .onChange(of: model.controller.lastRecord?.id) { _, _ in checkPractice() }
    }

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeStep(onStart: advance)
        case .microphone:
            MicrophoneStep(status: microphone)
                .padding(.bottom, Layout.Setup.footerHeight)
        case .accessibility:
            AccessibilityStep(
                granted: accessibilityGranted,
                needsRelaunch: needsRelaunch,
                relaunchFailed: relaunchFailed
            )
            .padding(.bottom, Layout.Setup.footerHeight)
        case .model:
            ModelStep(engine: model.settings.engine, state: modelState)
                .padding(.bottom, Layout.Setup.footerHeight)
                .onAppear(perform: prepareModel)
        case .shortcut:
            ShortcutStep(
                settings: model.settings,
                fnHasSystemAction: preview?.fnHasSystemAction ?? SetupKit.fnKeyHasSystemAction,
                wisprRunning: preview?.wisprRunning ?? SetupKit.isWisprFlowRunning,
                onChange: { model.controller.reloadShortcuts() }
            )
            .padding(.bottom, Layout.Setup.footerHeight)
        case .practice:
            PracticeStep(
                key: model.settings.pushToTalkKey,
                phase: phase,
                hotkeyActive: hotkeyActive,
                succeeded: practiceSucceeded,
                initialText: preview?.practiceText,
                onFixAccessibility: { go(to: .accessibility) }
            )
            .padding(.bottom, Layout.Setup.footerHeight)
            .onAppear {
                if preview == nil { practiceBaseline = model.controller.lastRecord?.id }
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
                    .keyboardShortcut(.defaultAction)
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
            case .denied: return FooterAction(title: "Open System Settings") { Permissions.openMicrophoneSettings() }
            case .notDetermined: return FooterAction(title: "Allow Microphone", run: requestMicrophone)
            }
        case .accessibility:
            if !accessibilityGranted {
                return FooterAction(title: "Open System Settings") {
                    // The prompt is what adds Murmur to the Accessibility list; opening the
                    // pane directly saves a click in the system alert.
                    Permissions.promptForAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
            if needsRelaunch && SetupKit.canRelaunch && !relaunchFailed {
                return FooterAction(title: "Relaunch Murmur") {
                    if !SetupKit.relaunch() { relaunchFailed = true }
                }
            }
            return FooterAction(title: "Continue", run: advance)
        case .model, .shortcut:
            return FooterAction(title: "Continue", run: advance)
        case .practice:
            return FooterAction(title: practiceSucceeded ? "Start Using Murmur" : "Finish", run: finish)
        }
    }

    private var secondary: FooterAction? {
        switch step {
        case .microphone where microphone != .granted:
            return FooterAction(title: "Skip", run: advance)
        case .accessibility where !accessibilityGranted:
            return FooterAction(title: "Skip", run: advance)
        case .accessibility where needsRelaunch && SetupKit.canRelaunch && !relaunchFailed:
            return FooterAction(title: "Later", run: advance)
        case .model where SetupKit.isFailed(modelState):
            return FooterAction(title: "Try Again", run: prepareModel)
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
        guard step == .accessibility, model.controller.isHotkeyActive else { return }
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
              let record = model.controller.lastRecord,
              record.id != practiceBaseline, record.hasText
        else { return }
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

/// The shared shape of a step: glyph, serif title, a calm paragraph, then the step's controls.
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
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            SetupKit.AppMark(size: Layout.Setup.appIcon)
                .scaleEffect(appeared || reduceMotion ? 1 : Motion.pressedScale)
                .opacity(appeared ? 1 : 0)
            VStack(spacing: Spacing.xs) {
                Text("Murmur")
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
                Text("Setup takes about a minute.")
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
}

// MARK: - 2 · Microphone

private struct MicrophoneStep: View {
    let status: SetupPreview.Microphone

    var body: some View {
        StepScaffold(
            symbol: "mic",
            done: status == .granted,
            title: "Let Murmur hear you",
            message: "Murmur only listens while you hold your shortcut. What you say becomes text right here on this Mac."
        ) {
            VStack(spacing: Spacing.m) {
                PermissionRow(symbol: "mic", title: "Microphone", state: rowState)
                if status == .denied {
                    SetupKit.Callout(
                        symbol: "exclamationmark.triangle.fill",
                        tint: Palette.warning,
                        fill: Palette.warningSoft,
                        text: "Microphone access is turned off. Turn on Murmur in Privacy & Security → Microphone, then come back."
                    )
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
    let relaunchFailed: Bool

    var body: some View {
        StepScaffold(
            symbol: "keyboard",
            done: granted && !needsRelaunch,
            title: "Let Murmur type for you",
            message: "Accessibility access lets Murmur notice your shortcut in any app, then type into the field you're using."
        ) {
            VStack(spacing: Spacing.m) {
                if granted {
                    PermissionRow(symbol: "accessibility", title: "Accessibility", state: .granted)
                } else {
                    instructions
                }
                if needsRelaunch {
                    SetupKit.Callout(
                        symbol: "arrow.clockwise",
                        tint: Palette.inkSecondary,
                        fill: Palette.sunken,
                        text: relaunchHint
                    )
                }
            }
        }
    }

    private var relaunchHint: String {
        if relaunchFailed || !SetupKit.canRelaunch {
            return "Access is on. Quit Murmur and open it again so macOS lets it hear your shortcut."
        }
        return "Access is on. macOS needs Murmur to restart once before it can hear your shortcut."
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            InstructionLine(number: 1, text: "Click Open System Settings below.")
            InstructionLine(number: 2, text: "Turn on Murmur in the Accessibility list.")
            InstructionLine(number: 3, text: "Come back here. This page updates by itself.")
            Divider().overlay(Palette.hairline)
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Waiting for access…")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .setupCard()
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

    var body: some View {
        StepScaffold(
            symbol: "arrow.down",
            done: state == .ready,
            title: "Get the speech model",
            message: "Murmur turns speech into text on this Mac. The model downloads once, then works offline."
        ) {
            VStack(spacing: Spacing.m) {
                card
                if SetupKit.progress(of: state) != nil || state == .loading {
                    Text("You can carry on. It keeps going in the background.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
        }
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
                    text: "The download stopped: \(message)"
                )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var key: PushToTalkKey { settings.pushToTalkKey }
    private var glyph: String { SetupKit.glyph(for: key) }

    var body: some View {
        StepScaffold(
            title: "Choose your shortcut",
            message: "Hold it while you talk. Let go, and your words appear."
        ) {
            VStack(spacing: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    ForEach(SetupKit.orderedKeys, id: \.self) { option in
                        KeyOption(key: option, selected: option == key) {
                            withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
                                settings.pushToTalkKey = option
                            }
                            onChange()
                        }
                    }
                }
                gestures
                if key == .fn && fnHasSystemAction {
                    SetupKit.Callout(
                        symbol: "globe",
                        tint: Palette.warning,
                        fill: Palette.warningSoft,
                        text: "The 🌐 key also opens Emoji or Dictation. Set “Press 🌐 key to” to “Do Nothing” so only Murmur hears it."
                    ) {
                        Button("Open Keyboard Settings…", action: SetupKit.openKeyboardSettings)
                            .buttonStyle(SetupKit.InlineLinkStyle())
                    }
                } else if wisprRunning {
                    SetupKit.Callout(
                        symbol: "exclamationmark.triangle.fill",
                        tint: Palette.warning,
                        fill: Palette.warningSoft,
                        text: "Wispr Flow is running. If it uses the same key, both apps will listen at once."
                    )
                }
            }
        }
    }

    private var gestures: some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .top, spacing: 0) {
                GestureHint(keys: [glyph], caption: "Hold to talk")
                if settings.handsFreeEnabled {
                    GestureHint(keys: [glyph, glyph], caption: "Double-tap for hands-free")
                }
                GestureHint(keys: ["esc"], caption: "Cancel")
            }
            if settings.handsFreeEnabled {
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
                    .fill(selected ? Palette.emberSoft : (hovering ? Palette.surfaceHover : Palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .strokeBorder(
                        selected ? Palette.ember : Palette.hairline,
                        lineWidth: selected ? Layout.Setup.selectionStroke : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
        .buttonStyle(.plain)
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
    let succeeded: Bool
    let initialText: String?
    let onFixAccessibility: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var keyName: String { SetupKit.name(for: key) }

    var body: some View {
        StepScaffold(
            symbol: "waveform",
            done: succeeded,
            title: succeeded ? "That's it." : "Give it a try",
            message: succeeded
                ? "Murmur works like this in every app. Hold \(keyName), speak, let go."
                : "Click in the box, hold \(keyName), and say:"
        ) {
            VStack(spacing: Spacing.m) {
                if !succeeded {
                    Text("“Murmur is my new favourite way to write.”")
                        .font(Typography.transcriptLarge)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, Spacing.xs)
                }
                TextField(
                    "Practice",
                    text: $text,
                    prompt: Text("Your words will appear here.").foregroundStyle(Palette.inkTertiary),
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .font(Typography.transcript)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(Spacing.transcriptLine)
                    .lineLimit(3, reservesSpace: true)
                    .focused($focused)
                    .padding(Spacing.m)
                    .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Palette.sunken))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                            .strokeBorder(focused ? Palette.hairlineStrong : Palette.hairline)
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
                Text("Murmur can't hear your shortcut yet.")
                    .foregroundStyle(Palette.inkSecondary)
                Button("Fix Accessibility", action: onFixAccessibility)
                    .buttonStyle(SetupKit.InlineLinkStyle())
            }
            .font(Typography.callout)
        } else if phase.isRecording {
            HStack(spacing: Spacing.s) {
                SetupKit.StatusDot(color: Palette.ember)
                Text("Listening… let go when you're done.")
                    .foregroundStyle(Palette.ink)
            }
            .font(Typography.callout)
        } else if phase.isBusy {
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Writing it down…")
                    .foregroundStyle(Palette.inkSecondary)
            }
            .font(Typography.callout)
        } else if succeeded {
            Label("Typed by Murmur", systemImage: "checkmark.circle.fill")
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Palette.success)
        } else {
            Text("Waiting for you to hold \(keyName)…")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkTertiary)
        }
    }
}
