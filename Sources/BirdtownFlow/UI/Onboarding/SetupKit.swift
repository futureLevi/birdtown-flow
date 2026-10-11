import AppKit
import MurmurKit
import SwiftUI

/// Small controls shared by onboarding, Settings and the menu bar.
///
/// Namespaced so they can't collide with the shared `UI/Components` library being built
/// alongside; once that lands, these can be swapped for its equivalents.
enum SetupKit {}

// MARK: - Snapshot facts

/// Service state faked for snapshots. In the running app this is `nil` and views read the
/// live model; snapshots inject it so every state (permission denied, model at 42 %…) can be
/// rendered without a real Mac's permissions — and so no side effects run while rendering.
struct SetupPreview {
    enum Microphone { case notDetermined, granted, denied }

    var microphone: Microphone = .granted
    var accessibility = true
    var hotkeyActive = true
    var modelState: ModelManager.State = .ready
    var downloaded: Set<SpeechEngineChoice> = [.parakeetUltra, .apple]
    var phase: DictationController.Phase = .idle
    var practiceSucceeded = false
    var fnHasSystemAction = false
    var wisprRunning = false
    var devices: [AudioInputDevice] = []
    var launchAtLogin = true
    var keySaved = false
    /// Text already in the practice field, as if Birdtown Flow had just typed it.
    var practiceText: String?
    /// The engine History recorded for the practice dictation, e.g. "Apple Speech" when it
    /// stood in for a Parakeet model that was still downloading.
    var practiceEngine: String?
    /// Whether Birdtown Flow runs from an app bundle and can relaunch itself. `nil` reads the
    /// real answer, which is `false` on the snapshot runner (not a bundle).
    var canRelaunch: Bool?
    /// As if the user had already clicked Open System Settings on a permission step.
    var openedSettings = false
}

private struct SetupPreviewKey: EnvironmentKey {
    static var defaultValue: SetupPreview? { nil }
}

extension EnvironmentValues {
    var setupPreview: SetupPreview? {
        get { self[SetupPreviewKey.self] }
        set { self[SetupPreviewKey.self] = newValue }
    }
}

// MARK: - System facts

@MainActor
extension SetupKit {
    /// Push-to-talk keys in the order we suggest them: fn first, it's the easiest to reach.
    /// Anything else comes from the shortcut recorder.
    static var orderedKeys: [PushToTalkKey] { PushToTalkKey.quickPicks }

    /// The quick picks, plus `current` when it was recorded, so a picker can show it selected.
    static func pickerKeys(including current: PushToTalkKey) -> [PushToTalkKey] {
        current.isQuickPick ? orderedKeys : orderedKeys + [current]
    }

    /// The symbol printed on the key: "fn", "⌥", "⌘"; a chord's keys run together: "⌃⌥D".
    static func glyph(for key: PushToTalkKey) -> String {
        key.glyphs.joined()
    }

    /// One keycap per key: ["fn"], ["⌃", "⌥", "D"].
    static func keys(for key: PushToTalkKey) -> [String] {
        key.glyphs
    }

    /// The key spelled out — "Right Option", "Fn (Globe)" — for captions and VoiceOver. A
    /// chord reads as printed ("⌃⌥D"), which is shorter in a sentence than its spoken name.
    static func name(for key: PushToTalkKey) -> String {
        switch key {
        case .modifier(let modifier): modifier.spokenName
        case .keys(let chord): chord.displayName
        }
    }

    /// The hands-free shortcut's keycaps when it has one of its own: ["⌃", "⌥"] or the
    /// recorded chord's.
    static func handsFreeKeys(_ settings: Settings) -> [String] {
        settings.handsFreeChord?.glyphs ?? ["⌃", "⌥"]
    }

    /// "⌃⌥", or the recorded chord, for sentences like "Press ⌃⌥ again to finish."
    static func handsFreeName(_ settings: Settings) -> String {
        handsFreeKeys(settings).joined()
    }

    /// Whether pressing 🌐/fn on its own also does something (emoji picker, input source,
    /// Dictation), which would fire alongside Birdtown Flow. `0` is "Do Nothing"; a missing value
    /// means the system default, which is never "Do Nothing".
    ///
    /// This is a system preference, read-only, so it deliberately doesn't live in `Settings`.
    static var fnKeyHasSystemAction: Bool {
        let value = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        return value != 0
    }

    /// Wispr Flow listens on fn by default; two apps on one key both start recording.
    static var isWisprFlowRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.lowercased().contains("wispr") == true
        }
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            _ = NSWorkspace.shared.open(url)
        }
    }

    /// Relaunching only makes sense from an app bundle (not `swift run`).
    static var canRelaunch: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Set while a relaunch is under way, so a second click can't start a second instance.
    private(set) static var isRelaunching = false

    /// Opens a fresh instance of Birdtown Flow, then quits this one. macOS sometimes only lets a
    /// process create its event tap after a restart that follows the Accessibility grant.
    /// The new instance resumes onboarding where this one was (see
    /// `OnboardingWindowController.show`). If macOS refuses to open it, this instance keeps
    /// running and says so.
    static func relaunch() {
        guard !isRelaunching else { return }
        isRelaunching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            // Called off the main thread; carry only a string across.
            let failure = error?.localizedDescription
            Task { @MainActor in
                guard let failure else {
                    NSApp.terminate(nil)
                    return
                }
                SetupKit.isRelaunching = false
                Log.ui.error("relaunch failed: \(failure, privacy: .public)")
                let alert = NSAlert()
                alert.messageText = "Birdtown Flow couldn't restart itself"
                alert.informativeText = "Quit Birdtown Flow and open it again from Applications to finish turning on your shortcut."
                alert.runModal()
            }
        }
    }

    /// Short, human description of the speech model's state.
    static func describe(_ state: ModelManager.State) -> String {
        if case .downloading(let progress) = state {
            guard let progress else { return "Downloading…" }
            return "Downloading · \(percent(progress))"
        }
        if case .failed(let message) = state { return message }
        if state == .loading { return "Getting ready…" }
        if state == .ready { return "Ready" }
        return "Not downloaded yet"
    }

    /// "42%", in the user's locale, the same way the main window formats it.
    static func percent(_ fraction: Double) -> String {
        min(max(fraction, 0), 1).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Download progress 0…1 when it is known.
    static func progress(of state: ModelManager.State) -> Double? {
        if case .downloading(let progress) = state { return progress }
        return nil
    }

    static func isFailed(_ state: ModelManager.State) -> Bool {
        if case .failed = state { return true }
        return false
    }

    /// The engine standing in for `engine` in `state`, for snapshots, which have no live
    /// `ModelManager`. Nothing loaded from before, so it's Apple Speech or nothing. The live
    /// answer is `ModelManager.standInName`.
    static func standIn(for engine: SpeechEngineChoice, state: ModelManager.State) -> String? {
        EngineFallback.standIn(
            selected: engine.displayName,
            selectedIsDownloadable: engine.isParakeet,
            selectedReady: state == .ready,
            loaded: nil
        )
    }

    /// "Using Apple Speech until Parakeet Ultra is ready · 42%", or `nil` when `engine` is
    /// ready or nothing stands in for it.
    static func standInNote(_ standIn: String?, for engine: SpeechEngineChoice, state: ModelManager.State) -> String? {
        guard let standIn, state != .ready else { return nil }
        return EngineFallback.note(
            standIn: standIn,
            selected: engine.displayName,
            progress: progress(of: state).map { percent($0) }
        )
    }
}

// MARK: - Keycap

extension SetupKit {
    /// A keyboard key drawn the way it is printed: "fn", "⌥", "esc".
    /// Draws the shared `KeyCap`, so setup and the main window show the same key.
    struct KeyCap: View {
        let label: String
        var large = false

        var body: some View {
            SharedKeyCap(label: label, size: large ? .large : .regular)
        }
    }

    /// Several keys pressed together, e.g. ⌃ ⌥ V.
    struct KeyCombo: View {
        let keys: [String]

        var body: some View {
            HStack(spacing: Spacing.xs) {
                ForEach(keys, id: \.self) { KeyCap(label: $0) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(keys.joined(separator: " "))
        }
    }
}

/// The shared component kit's types, named from file scope: inside `SetupKit` the bare
/// names would resolve to SetupKit's own wrappers.
private typealias SharedKeyCap = KeyCap
private typealias SharedStatusDot = StatusDot

// MARK: - Buttons

extension SetupKit {
    /// The one filled button on a screen: a navy pill (porcelain in dark mode), like the
    /// logo's tile and ring. Never more than one per view.
    struct PrimaryButtonStyle: ButtonStyle {
        var fullWidth = false
        /// A taller, wider button for a screen's single moment, like Get Started.
        var large = false

        func makeBody(configuration: Configuration) -> some View {
            PrimaryButtonBody(configuration: configuration, fullWidth: fullWidth, large: large)
        }
    }

    /// A quiet bordered pill for secondary actions: the same shape as the primary, none of
    /// its weight.
    ///
    /// Draws `.flowSecondary`, so setup's secondary pills match the main window's (and a
    /// `role: .destructive` button reads as destructive).
    struct SecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            FlowSecondaryButtonStyle().makeBody(configuration: configuration)
        }
    }

    /// Text-only, for Back / Skip: present but never competing with the primary action.
    struct QuietButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            QuietButtonBody(configuration: configuration)
        }
    }

    /// An inline link inside a sentence or callout, in Signal blue like every link.
    struct InlineLinkStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Palette.accentInk)
                .opacity(configuration.isPressed ? Layout.Setup.pressedOpacity : 1)
                .contentShape(Rectangle())
        }
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fullWidth: Bool
    let large: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var fill: Color {
        guard isEnabled else { return Palette.primaryFill }
        if configuration.isPressed { return Palette.primaryFillPressed }
        return hovering ? Palette.primaryFillHover : Palette.primaryFill
    }

    var body: some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .font(Typography.bodyEmphasis)
            .foregroundStyle(Palette.onPrimary)
            .padding(.horizontal, large ? Spacing.xxxl : Spacing.l)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(
                minWidth: Layout.Setup.buttonMinWidth,
                minHeight: large ? Layout.Setup.menuButtonHeight : Layout.Setup.buttonHeight
            )
            .background(shape.fill(fill))
            .opacity(isEnabled ? 1 : Interaction.disabledOpacity)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Interaction.pressedScale : 1)
            .contentShape(shape)
            .flowFocusRing(shape)
            .onHover { hovering = $0 }
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: hovering)
    }
}

private struct QuietButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(Typography.body)
            .foregroundStyle(hovering && isEnabled ? Palette.ink : Palette.inkSecondary)
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: Layout.Setup.buttonHeight)
            .opacity(isEnabled ? (configuration.isPressed ? Layout.Setup.pressedOpacity : 1) : Interaction.disabledOpacity)
            .contentShape(Rectangle())
            .flowFocusRing(Capsule(style: .continuous))
            .onHover { hovering = $0 }
            .animation(Motion.resolve(Motion.fadeFast, reduceMotion: reduceMotion), value: hovering)
    }
}

// MARK: - Progress and status

extension SetupKit {
    /// A slim determinate bar. The fill is the spectrum, because a download is live, and it
    /// is laid across the whole track so the colour warms as the bar grows.
    struct ProgressBar: View {
        let fraction: Double

        var body: some View {
            SpectrumProgressBar(progress: fraction, height: Layout.Setup.progressBarHeight)
        }
    }

    /// A filled circle for settled states: green when ready, amber or red when something needs
    /// attention, Signal blue for a call to action. Anything live is a `SpectrumOrb` instead.
    struct StatusDot: View {
        let color: Color

        var body: some View {
            SharedStatusDot(color: color)
        }
    }

    /// A one-line notice with an icon, for warnings and confirmations inside a card.
    struct Callout<Accessory: View>: View {
        let symbol: String
        let tint: Color
        let fill: Color
        let text: String
        @ViewBuilder var accessory: Accessory

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(text)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    accessory
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.m)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(fill))
        }
    }
}

extension SetupKit.Callout where Accessory == EmptyView {
    init(symbol: String, tint: Color, fill: Color, text: String) {
        self.init(symbol: symbol, tint: tint, fill: fill, text: text) { EmptyView() }
    }
}

// MARK: - Card

extension View {
    /// A raised surface with a hairline border: the container for every group of controls.
    func setupCard(padding: CGFloat = Spacing.l) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(Palette.hairline))
            .elevation(Elevation.card)
    }
}

// MARK: - App mark

extension SetupKit {
    /// Birdtown Flow's app icon, wherever setup shows it. Wraps the brand artwork so the onboarding
    /// welcome, the About pane and the menu bar header all match the Dock icon exactly.
    struct AppMark: View {
        let size: CGFloat
        /// Kept for call-site compatibility: the artwork carries its own soft shadow, which is
        /// already proportional to the size, so small marks don't smudge.
        var elevated = true

        var body: some View {
            AppIconArtwork(size: size)
                .accessibilityHidden(true)
        }
    }
}
