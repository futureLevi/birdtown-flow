import SwiftUI

/// What the HUD's buttons do. No-ops by default, for snapshots.
struct HUDActions {
    var stop: @MainActor () -> Void = {}
    var cancel: @MainActor () -> Void = {}
    /// Click on the idle pill: start a hands-free dictation.
    var activate: @MainActor () -> Void = {}
}

/// The floating pill. One dark capsule whose size springs between states while its content
/// cross-fades inside it. Driven entirely by a plain `HUDState`.
///
/// The view fills the panel (`Layout.HUD.panelSize`) and keeps the pill bottom-aligned above
/// a shadow margin, so the window itself never moves or resizes.
struct HUDView: View {
    let state: HUDState
    /// Snapshots pass a fixed time so animated states render deterministically.
    var frozenTime: Double?
    /// Snapshots pin this so both motion variants can be reviewed whatever the host's setting.
    var reduceMotionOverride: Bool?
    var actions = HUDActions()

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var failureCount = 0

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let size = HUDMetrics.pillSize(for: state)
        let kind = state.kind

        ZStack(alignment: .bottom) {
            pill(size: size, kind: kind)
                .padding(.bottom, Layout.HUD.shadowMargin)
        }
        .frame(width: Layout.HUD.panelSize.width, height: Layout.HUD.panelSize.height, alignment: .bottom)
        .onChange(of: state.failureMessage) { _, message in
            // A new failure shakes the pill once. Snapshots and Reduce Motion stay still.
            guard message != nil, frozenTime == nil, !reduceMotion else { return }
            failureCount += 1
        }
    }

    private func pill(size: CGSize, kind: HUDState.Kind) -> some View {
        ZStack {
            // At rest the whole pill is faded, so its edge needs more light to stay findable
            // on dark content.
            HUDPillBody(stroke: kind == .idle || kind == .hidden ? Palette.HUD.idleStroke : Palette.HUD.stroke)
            content(size: size, kind: kind)
                .frame(width: size.width, height: size.height)
                .clipShape(Capsule(style: .continuous))
        }
        .frame(width: size.width, height: size.height)
        .opacity(opacity(for: kind))
        .scaleEffect(scale(for: kind), anchor: .bottom)
        .phaseAnimator(Motion.shakeOffsets, trigger: failureCount) { content, offset in
            content.offset(x: offset)
        } animation: { _ in
            Motion.shakeStep
        }
        .animation(Motion.resolve(Motion.pill, reduceMotion: reduceMotion), value: kind)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(state.accessibilityDescription))
        .accessibilityHidden(kind == .hidden)
    }

    @ViewBuilder
    private func content(size: CGSize, kind: HUDState.Kind) -> some View {
        switch kind {
        case .hidden, .idle:
            Color.clear
        case .hint:
            HUDIdleHint(keyName: state.keyName, action: actions.activate)
                .transition(contentTransition)
        case .listening, .handsFree, .transcribing, .polishing:
            HUDLiveContent(state: state, size: size, frozenTime: frozenTime, reduceMotion: reduceMotion,
                           actions: actions)
                .transition(contentTransition)
        case .done:
            HUDDrawnCheck(animated: frozenTime == nil && !reduceMotion)
                .transition(contentTransition)
        case .cancelled:
            Image(systemName: "xmark")
                .font(Typography.hudGlyph)
                .foregroundStyle(Palette.HUD.inkSecondary)
                .transition(contentTransition)
                .accessibilityHidden(true)
        case .failed:
            HUDFailure(message: state.failureMessage ?? "")
                .transition(contentTransition)
        }
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .scale(scale: 0.9))
    }

    private func opacity(for kind: HUDState.Kind) -> Double {
        switch kind {
        case .hidden: 0
        case .idle: Palette.HUD.idleOpacity
        case .cancelled: 0.85
        default: 1
        }
    }

    private func scale(for kind: HUDState.Kind) -> CGFloat {
        switch kind {
        case .hidden: 0.6
        case .cancelled: 0.92
        default: 1
        }
    }
}

/// The capsule and its shadow, drawn in one `Canvas`. The shadow is stacked translucent
/// capsules rather than a layer shadow, so it is identical on screen and in offscreen
/// snapshots (where layer shadows render flipped), and it costs a dozen fills.
struct HUDPillBody: View {
    var stroke = Palette.HUD.stroke

    var body: some View {
        let stroke = self.stroke
        Canvas { context, canvasSize in
            let margin = Layout.HUD.shadowMargin
            let pill = CGRect(origin: .zero, size: canvasSize).insetBy(dx: margin, dy: margin)
            let shadow = Elevation.hud
            let layers = 14
            for layer in 1...layers {
                let fraction = CGFloat(layer) / CGFloat(layers)
                let rect = pill
                    .insetBy(dx: -shadow.radius * fraction, dy: -shadow.radius * fraction)
                    .offsetBy(dx: 0, dy: shadow.y * fraction)
                context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .continuous),
                             with: .color(Palette.HUD.shadow.opacity(Palette.HUD.shadowLayerOpacity)))
            }
            // A tight contact shadow so the pill sits on the screen rather than floating in fog.
            let contact = pill.insetBy(dx: -1, dy: -1).offsetBy(dx: 0, dy: 1)
            context.fill(Path(roundedRect: contact, cornerRadius: contact.height / 2, style: .continuous),
                         with: .color(Palette.HUD.shadow.opacity(Palette.HUD.contactShadowOpacity)))

            let capsule = Path(roundedRect: pill, cornerRadius: pill.height / 2, style: .continuous)
            context.fill(capsule, with: .color(Palette.HUD.fill))
            let edge = pill.insetBy(dx: 0.5, dy: 0.5)
            context.stroke(Path(roundedRect: edge, cornerRadius: edge.height / 2, style: .continuous),
                           with: .color(stroke), lineWidth: 1)
        }
        .padding(-Layout.HUD.shadowMargin)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - State content

/// Hovering the idle pill: it brightens and grows to say how to start.
struct HUDIdleHint: View {
    let keyName: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: Layout.HUD.hintSpacing) {
                Text(HUDMetrics.hintLead)
                HUDKeycap(key: keyName)
                Text(HUDMetrics.hintTrail)
            }
            .font(Typography.hud)
            .foregroundStyle(Palette.HUD.ink)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start dictating")
        .accessibilityHint("Or hold \(keyName) while you speak")
    }
}

struct HUDKeycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(Typography.hudKeycap)
            .foregroundStyle(Palette.HUD.ink)
            .padding(.horizontal, Layout.HUD.keycapPadding)
            .frame(height: Layout.HUD.keycapHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(Palette.HUD.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .strokeBorder(Palette.HUD.stroke, lineWidth: 1)
            )
    }
}

/// Done: a check that draws itself. A nod, not a celebration.
struct HUDDrawnCheck: View {
    let animated: Bool
    @State private var progress: CGFloat = 0

    var body: some View {
        let side = Layout.HUD.checkSize
        Path { path in
            path.move(to: CGPoint(x: side * 0.16, y: side * 0.54))
            path.addLine(to: CGPoint(x: side * 0.41, y: side * 0.78))
            path.addLine(to: CGPoint(x: side * 0.86, y: side * 0.24))
        }
        .trim(from: 0, to: animated ? progress : 1)
        .stroke(Palette.HUD.success, style: StrokeStyle(lineWidth: Layout.HUD.checkStroke, lineCap: .round, lineJoin: .round))
        .frame(width: side, height: side)
        .onAppear {
            guard animated else { return }
            withAnimation(Motion.checkDraw) { progress = 1 }
        }
        .accessibilityHidden(true)
    }
}

struct HUDFailure: View {
    let message: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            ZStack {
                Circle().fill(Palette.HUD.dangerSoft)
                Image(systemName: "exclamationmark")
                    .font(Typography.hudGlyph)
                    .foregroundStyle(Palette.HUD.danger)
            }
            .frame(width: Layout.HUD.failureGlyph, height: Layout.HUD.failureGlyph)
            .accessibilityHidden(true)

            Text(message)
                .font(Typography.hud)
                .foregroundStyle(Palette.HUD.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Layout.HUD.messageMaxWidth, alignment: .leading)
        }
        .padding(.horizontal, Layout.HUD.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// Hands-free Stop: the primary action, so it carries the Ember and breathes with the
/// recording it ends.
struct HUDStopButton: View {
    let isHovered: Bool
    let breath: Double
    let action: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(Palette.HUD.ember)
                    .opacity(isHovered ? 1 : 0.86 + 0.14 * breath)
                RoundedRectangle(cornerRadius: Layout.HUD.stopGlyphRadius, style: .continuous)
                    .fill(Palette.HUD.onEmber)
                    .frame(width: Layout.HUD.stopGlyph, height: Layout.HUD.stopGlyph)
            }
            .frame(width: Layout.HUD.buttonSize, height: Layout.HUD.buttonSize)
            .scaleEffect(isHovered ? 1.08 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel("Stop and insert")
        .help("Stop and insert")
    }
}

struct HUDIconButton: View {
    let symbol: String
    let label: String
    let isHovered: Bool
    let action: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(Typography.hudGlyph)
                .foregroundStyle(isHovered ? Palette.HUD.ink : Palette.HUD.inkSecondary)
                .frame(width: Layout.HUD.buttonSize, height: Layout.HUD.buttonSize)
                .background(Circle().fill(isHovered ? Palette.HUD.controlHover : Palette.HUD.control))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel(label)
        .help(label)
    }
}
