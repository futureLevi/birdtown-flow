import AppKit
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
    /// Text already in the practice field, as if Murmur had just typed it.
    var practiceText: String?
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
    static var orderedKeys: [PushToTalkKey] {
        [.fn] + PushToTalkKey.allCases.filter { $0 != .fn }
    }

    /// The symbol printed on the key: "fn", "⌥", "⌘".
    static func glyph(for key: PushToTalkKey) -> String {
        key.displayName.split(separator: " ").last.map(String.init) ?? key.displayName
    }

    /// The key spelled out — "Right Option" — for captions and VoiceOver.
    static func name(for key: PushToTalkKey) -> String {
        let words = ["⌥": "Option", "⌘": "Command", "⌃": "Control", "⇧": "Shift"]
        return key.displayName.split(separator: " ")
            .map { words[String($0)] ?? String($0) }
            .joined(separator: " ")
    }

    /// Whether pressing 🌐/fn on its own also does something (emoji picker, input source,
    /// Dictation), which would fire alongside Murmur. `0` is "Do Nothing"; a missing value
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

    /// Quits and reopens Murmur. macOS sometimes only lets a process create its event tap
    /// after a restart that follows the Accessibility grant.
    /// - Returns: `false` if the relauncher couldn't be started (Murmur keeps running).
    static func relaunch() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to exit before reopening, so the new instance is a fresh
        // launch rather than a reactivation of the dying one. The bundle path arrives as $0
        // so it never needs quoting.
        let pid = ProcessInfo.processInfo.processIdentifier
        process.arguments = [
            "-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
            Bundle.main.bundleURL.path,
        ]
        do {
            try process.run()
        } catch {
            Log.ui.error("relaunch failed: \(error.localizedDescription)")
            return false
        }
        NSApp.terminate(nil)
        return true
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

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded())) %"
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
}

// MARK: - Keycap

extension SetupKit {
    /// A keyboard key drawn the way it is printed: "fn", "⌥", "esc".
    struct KeyCap: View {
        let label: String
        var large = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: large ? Radius.m : Radius.xs, style: .continuous)
            Text(label)
                .font(large ? Typography.keycapLarge : Typography.keycap)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, large ? Spacing.m : Spacing.xs + Spacing.xxs)
                .frame(
                    minWidth: large ? Layout.Setup.keyCapLarge : Layout.Setup.keyCap,
                    minHeight: large ? Layout.Setup.keyCapLarge : Layout.Setup.keyCap
                )
                .background(shape.fill(Palette.surface))
                .overlay(shape.strokeBorder(Palette.hairlineStrong))
                .background(
                    shape.fill(Palette.hairlineStrong)
                        .offset(y: large ? Layout.Setup.keyLip * 2 : Layout.Setup.keyLip)
                )
                .padding(.bottom, large ? Layout.Setup.keyLip * 2 : Layout.Setup.keyLip)
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

// MARK: - Buttons

extension SetupKit {
    /// The one filled button on a screen. Ember, because it is the thing to press.
    struct PrimaryButtonStyle: ButtonStyle {
        var fullWidth = false
        /// A taller, wider button for a screen's single moment, like Get Started.
        var large = false

        func makeBody(configuration: Configuration) -> some View {
            PrimaryButtonBody(configuration: configuration, fullWidth: fullWidth, large: large)
        }
    }

    /// A quiet bordered button for secondary actions.
    struct SecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            SecondaryButtonBody(configuration: configuration)
        }
    }

    /// Text-only, for Back / Skip: present but never competing with the primary action.
    struct QuietButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            QuietButtonBody(configuration: configuration)
        }
    }

    /// An inline link inside a sentence or callout: underlined ink rather than system blue,
    /// which would fight the warm palette.
    struct InlineLinkStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(Typography.callout.weight(.medium))
                .underline()
                .foregroundStyle(Palette.ink)
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        configuration.label
            .font(Typography.bodyEmphasis)
            .foregroundStyle(Palette.onEmber)
            .padding(.horizontal, large ? Spacing.xxxl : Spacing.l)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(
                minWidth: Layout.Setup.buttonMinWidth,
                minHeight: large ? Layout.Setup.menuButtonHeight : Layout.Setup.buttonHeight
            )
            .background(shape.fill(Palette.ember))
            .overlay(shape.fill(Palette.onEmber.opacity(hovering && isEnabled && !configuration.isPressed ? Layout.Setup.hoverLift : 0)))
            .opacity(isEnabled ? (configuration.isPressed ? Layout.Setup.pressedOpacity : 1) : Layout.Setup.disabledOpacity)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.pressedScale : 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Motion.fadeFast, value: hovering)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        configuration.label
            .font(Typography.bodyEmphasis)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: Layout.Setup.buttonHeight - Spacing.xs)
            .background(shape.fill(hovering && isEnabled ? Palette.surfaceHover : Palette.surface))
            .overlay(shape.strokeBorder(Palette.hairlineStrong))
            .opacity(isEnabled ? (configuration.isPressed ? Layout.Setup.pressedOpacity : 1) : Layout.Setup.disabledOpacity)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.pressedScale : 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Motion.fadeFast, value: hovering)
    }
}

private struct QuietButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(Typography.body)
            .foregroundStyle(hovering && isEnabled ? Palette.ink : Palette.inkSecondary)
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: Layout.Setup.buttonHeight)
            .opacity(isEnabled ? (configuration.isPressed ? Layout.Setup.pressedOpacity : 1) : Layout.Setup.disabledOpacity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(Motion.fadeFast, value: hovering)
    }
}

// MARK: - Progress and status

extension SetupKit {
    /// A slim determinate bar in ink — calm, not an alarm.
    struct ProgressBar: View {
        let fraction: Double
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { proxy in
                let clamped = min(max(fraction, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.sunken)
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: max(proxy.size.height, proxy.size.width * clamped))
                }
            }
            .frame(height: Layout.Setup.progressBarHeight)
            .animation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion), value: fraction)
            .accessibilityElement()
            .accessibilityLabel("Download progress")
            .accessibilityValue(SetupKit.percent(fraction))
        }
    }

    /// A filled circle that signals state: Ember while listening, green when ready.
    struct StatusDot: View {
        let color: Color

        var body: some View {
            Circle()
                .fill(color)
                .frame(width: Layout.Setup.statusDot, height: Layout.Setup.statusDot)
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
    /// Murmur's mark until the brand artwork lands: a dark squircle with a quiet waveform that
    /// ends in one Ember dot, the live point where speech becomes text. Always dark, like the
    /// HUD, so it reads the same on paper and graphite.
    struct AppMark: View {
        let size: CGFloat
        /// Small marks (menu bar header) sit flat; a shadow at that size reads as a smudge.
        var elevated = true

        // Artwork geometry as fractions of the icon size — proportions of a drawing, not UI
        // metrics, so they live with the drawing.
        private let bars: [CGFloat] = [0.14, 0.27, 0.43, 0.31, 0.21, 0.12]
        private let barWidth: CGFloat = 0.055
        private let barGap: CGFloat = 0.048
        private let cornerRatio: CGFloat = 0.225
        private let dotRatio: CGFloat = 0.085

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
            ZStack {
                shape.fill(Palette.HUD.fill)
                HStack(spacing: size * barGap) {
                    ForEach(bars.indices, id: \.self) { index in
                        Capsule()
                            .fill(Palette.HUD.bar)
                            .frame(width: size * barWidth, height: size * bars[index])
                    }
                    Circle()
                        .fill(Palette.HUD.ember)
                        .frame(width: size * dotRatio, height: size * dotRatio)
                }
            }
            .frame(width: size, height: size)
            .overlay(shape.strokeBorder(Palette.HUD.stroke))
            .elevation(elevated ? Elevation.raised : Elevation.flat)
            .accessibilityHidden(true)
        }
    }
}
