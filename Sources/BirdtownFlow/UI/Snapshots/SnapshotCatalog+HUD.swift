import SwiftUI

// Owned by the hud agent: every HUD state, on a light and a dark backdrop.
//
// The renderer draws each shot in light and dark appearance; the backdrop follows the
// appearance (a document in light, a code editor in dark), so every state is reviewed over
// both kinds of content the pill has to sit on.
extension SnapshotCatalog {
    static var hud: [SnapshotRenderer.Shot] {
        var shots = HUDPreview.all.map { preview in
            SnapshotRenderer.Shot("hud-\(preview.name)", size: HUDPreview.sceneSize) {
                HUDPreviewScene(preview: preview)
            }
        }
        shots.append(SnapshotRenderer.Shot("hud-sheet", size: HUDPreview.sheetSize) {
            HUDPreviewSheet()
        })
        shots.append(SnapshotRenderer.Shot("hud-check-compare", size: HUDPreview.sceneSize) {
            HUDCheckComparison()
        })
        shots.append(SnapshotRenderer.Shot("brand-icon-512", size: CGSize(width: 512, height: 512)) {
            AppIconArtwork(size: 512)
        })
        shots.append(SnapshotRenderer.Shot("brand-icon-32", size: CGSize(width: 32, height: 32)) {
            AppIconArtwork(size: 32)
        })
        shots.append(SnapshotRenderer.Shot("brand-sheet", size: CGSize(width: 720, height: 600)) {
            BrandPreviewSheet()
        })
        return shots
    }
}

// The README animation (rendered into `frames/`) and exported stills (`media/`).
extension SnapshotCatalog {
    static var frames: [SnapshotRenderer.Shot] {
        (0..<HUDFilm.frameCount).map { index in
            SnapshotRenderer.Shot(String(format: "hud-frame-%03d", index), size: HUDFilm.size) {
                HUDFilmFrame(index: index)
            }
        }
    }

    static var media: [SnapshotRenderer.Shot] {
        [SnapshotRenderer.Shot("icon", size: CGSize(width: 512, height: 512)) {
            AppIconArtwork(size: 512, showsShadow: false)
        }]
    }
}

/// A named, frozen HUD state for review.
@MainActor
struct HUDPreview {
    let name: String
    let state: HUDState
    /// CI runners may have Reduce Motion on; previews pin it so the full design is reviewed.
    var reduceMotion = false

    static let sceneSize = CGSize(width: 480, height: 160)
    /// Two columns, as many rows as there are states.
    static var sheetSize: CGSize {
        CGSize(width: sceneSize.width * 2, height: sceneSize.height * CGFloat((all.count + 1) / 2))
    }
    /// Any fixed instant: animated states render deterministically at it.
    static let time: Double = 812_345_678.4

    static var all: [HUDPreview] {
        let start = Date(timeIntervalSinceReferenceDate: time - 42.4)
        return [
            HUDPreview(name: "idle", state: HUDState(phase: .idle)),
            HUDPreview(name: "idle-hover", state: HUDState(phase: .idle, hover: .pill)),
            HUDPreview(name: "listening-silence", state: HUDState(phase: .listening, level: 0.01, levels: levels(peak: 0.015))),
            HUDPreview(name: "listening-speech", state: HUDState(phase: .listening, level: 0.35, levels: levels(peak: 0.5))),
            HUDPreview(name: "listening-loud", state: HUDState(phase: .listening, level: 0.8, levels: levels(peak: 0.95))),
            HUDPreview(name: "handsfree", state: HUDState(phase: .listening, isHandsFree: true, level: 0.3,
                                                         levels: levels(peak: 0.45), recordingStartedAt: start)),
            HUDPreview(name: "handsfree-hover-stop", state: HUDState(phase: .listening, isHandsFree: true, level: 0.05,
                                                                    levels: levels(peak: 0.06), recordingStartedAt: start,
                                                                    hover: .stop)),
            HUDPreview(name: "handsfree-hover-cancel", state: HUDState(phase: .listening, isHandsFree: true, level: 0.05,
                                                                      levels: levels(peak: 0.06), recordingStartedAt: start,
                                                                      hover: .cancel)),
            HUDPreview(name: "transcribing", state: HUDState(phase: .transcribing)),
            // Polishing rises into a taller, flatter plateau than transcribing's low dome.
            HUDPreview(name: "polishing", state: HUDState(phase: .polishing)),
            HUDPreview(name: "transcribing-reduce-motion", state: HUDState(phase: .transcribing), reduceMotion: true),
            HUDPreview(name: "polishing-reduce-motion", state: HUDState(phase: .polishing), reduceMotion: true),
            HUDPreview(name: "done", state: HUDState(phase: .done)),
            HUDPreview(name: "done-copied", state: HUDState(phase: .done,
                                                           notice: "Copied · press ⌘V to paste")),
            // Copied because Accessibility is off: the pill links to the Accessibility pane.
            HUDPreview(name: "done-copied-accessibility", state: HUDState(phase: .done,
                                                                         notice: "Copied · press ⌘V, or allow Accessibility",
                                                                         actionLabel: "Open Accessibility settings")),
            // Inserted, but polish fell back: says why, and links to the History row.
            HUDPreview(name: "done-unpolished", state: HUDState(phase: .done,
                                                               notice: "Inserted without polish · Timed out",
                                                               actionLabel: "Show in History")),
            HUDPreview(name: "cancelled", state: HUDState(phase: .cancelled)),
            HUDPreview(name: "failed", state: HUDState(phase: .failed("Transcription took too long"))),
            // A failure with a next step: a chevron, lit while the pointer is on the pill.
            HUDPreview(name: "failed-actionable", state: HUDState(phase: .failed("Transcription took too long"),
                                                                 actionLabel: "Show in History")),
            HUDPreview(name: "failed-actionable-hover", state: HUDState(phase: .failed("Transcription took too long"),
                                                                       hover: .pill, actionLabel: "Show in History")),
            // Held the key and spoke, but the mic heard nothing (muted, or the wrong input).
            HUDPreview(name: "failed-no-speech", state: HUDState(phase: .failed(
                "Didn't hear anything · check MacBook Pro Microphone"), actionLabel: "Choose a microphone")),
            HUDPreview(name: "failed-no-words", state: HUDState(phase: .failed(
                "Didn't catch any words · it's saved in History"), actionLabel: "Show in History")),
            HUDPreview(name: "failed-mic-denied", state: HUDState(phase: .failed("Birdtown Flow needs microphone access"),
                                                                 actionLabel: "Open Microphone settings")),
            // The longest real engine message (ParakeetEngine): wraps to two lines, never truncates.
            HUDPreview(name: "failed-long", state: HUDState(phase: .failed(
                "Parakeet Ultra couldn't transcribe this recording. It's saved in History, so you can retry it."))),
            HUDPreview(name: "failed-long-actionable", state: HUDState(phase: .failed(
                "Parakeet Ultra couldn't transcribe this recording. It's saved in History, so you can retry it."),
                actionLabel: "Show in History")),
        ]
    }

    /// Speech-like level history: syllables under a slower phrase envelope, with the newest
    /// samples (drawn in the centre) near the phrase's peak.
    static func levels(peak: Float) -> [Float] {
        let count = DictationController.levelHistoryCount
        return (0..<count).map { index in
            let age = Double(count - 1 - index)
            let phrase = 0.62 + 0.38 * cos(age * 0.21)
            let syllable = abs(sin(age * 0.83 + 1.1))
            return Float(min(1, Double(peak) * phrase * (0.3 + 0.7 * syllable)))
        }
    }
}

/// The HUD as it sits on screen: over content, 18 pt above the Dock.
struct HUDPreviewScene: View {
    let preview: HUDPreview

    var body: some View {
        ZStack(alignment: .bottom) {
            HUDBackdrop()
            HUDView(state: preview.state, frozenTime: HUDPreview.time, reduceMotionOverride: preview.reduceMotion)
                .padding(.bottom, HUDBackdrop.dockVisible + Layout.HUD.bottomInset - Layout.HUD.shadowMargin)
        }
        .frame(width: HUDPreview.sceneSize.width, height: HUDPreview.sceneSize.height)
        .clipped()
    }
}

/// Every state on one page, for quick review.
struct HUDPreviewSheet: View {
    var body: some View {
        let previews = HUDPreview.all
        let columns = [GridItem(.fixed(HUDPreview.sceneSize.width), spacing: 0),
                       GridItem(.fixed(HUDPreview.sceneSize.width), spacing: 0)]
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(previews.indices, id: \.self) { index in
                HUDPreviewScene(preview: previews[index])
                    .overlay(alignment: .topTrailing) {
                        Text(previews[index].name)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                            .padding(Spacing.s)
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Palette.hairline).frame(width: 1)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
            }
        }
        .frame(width: HUDPreview.sheetSize.width, height: HUDPreview.sheetSize.height, alignment: .top)
        .background(Palette.canvas)
    }
}

/// A light document (light appearance) or a code editor (dark appearance), with the top of
/// the Dock along the bottom edge.
struct HUDBackdrop: View {
    static let dockVisible: CGFloat = 22

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            if colorScheme == .dark { editor } else { document }
            dock
        }
    }

    private var document: some View {
        let widths: [CGFloat] = [0.92, 0.88, 0.95, 0.28]
        return ZStack(alignment: .topLeading) {
            Palette.canvas
            VStack(alignment: .leading, spacing: Spacing.s) {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(Palette.ink.opacity(0.75))
                    .frame(width: 150, height: 9)
                    .padding(.bottom, Spacing.xs)
                ForEach(widths.indices, id: \.self) { index in
                    HStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .fill(Palette.ink.opacity(0.16))
                            .frame(width: 380 * widths[index], height: 6)
                        if index == widths.count - 1 {
                            // The caret, where the dictation will land.
                            Rectangle().fill(Palette.ink).frame(width: 1.5, height: 14)
                        }
                    }
                }
            }
            .padding(.leading, 48)
            .padding(.top, Spacing.xxl)
        }
    }

    private var editor: some View {
        let lines: [(indent: CGFloat, segments: [(width: CGFloat, colour: Color)])] = [
            (0, [(44, Palette.warning), (90, Palette.ink.opacity(0.7)), (18, Palette.inkTertiary)]),
            (16, [(30, Palette.danger.opacity(0.85)), (120, Palette.success.opacity(0.85))]),
            (16, [(54, Palette.warning), (70, Palette.ink.opacity(0.7)), (40, Palette.inkSecondary)]),
            (32, [(84, Palette.inkSecondary), (60, Palette.success.opacity(0.85))]),
            (0, [(12, Palette.inkTertiary)]),
        ]
        return ZStack(alignment: .topLeading) {
            Palette.canvas
            VStack(alignment: .leading, spacing: 9) {
                ForEach(lines.indices, id: \.self) { row in
                    HStack(spacing: Spacing.s) {
                        Text("\(row + 12)")
                            .font(Typography.mono)
                            .foregroundStyle(Palette.inkTertiary.opacity(0.6))
                            .frame(width: 22, alignment: .trailing)
                        HStack(spacing: 5) {
                            ForEach(lines[row].segments.indices, id: \.self) { index in
                                let segment = lines[row].segments[index]
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(segment.colour.opacity(0.75))
                                    .frame(width: segment.width, height: 6)
                            }
                        }
                        .padding(.leading, lines[row].indent)
                    }
                    .frame(height: 6)
                }
            }
            .padding(.leading, Spacing.l)
            .padding(.top, Spacing.l)
        }
    }

    private var dock: some View {
        HStack(spacing: Spacing.s) {
            ForEach(0..<7, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(Palette.hairlineStrong)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.s)
        .frame(height: 64, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
        .offset(y: 64 - Self.dockVisible)
    }
}

/// The icon at every size it ships at, plus the marks.
struct BrandPreviewSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            HStack(alignment: .bottom, spacing: Spacing.xxl) {
                ForEach([16, 32, 64, 128, 256] as [CGFloat], id: \.self) { side in
                    VStack(spacing: Spacing.s) {
                        AppIconArtwork(size: side)
                        Text("\(Int(side))")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
            HStack(spacing: Spacing.xxxl) {
                BrandWordmark()
                BrandMark(height: 28)
                HStack(spacing: Spacing.m) {
                    BrandGlyph(size: 16)
                    BrandGlyph(size: 16, isActive: true)
                    BrandGlyph(size: 22)
                }
                .foregroundStyle(Palette.ink)
            }
            // The spectrum orb: still, live (quiet and loud) and thinking, at each size, on
            // the window and on the pill's navy.
            VStack(alignment: .leading, spacing: Spacing.m) {
                orbs.padding(.horizontal, Spacing.xl).padding(.vertical, Spacing.m)
                orbs.padding(.horizontal, Spacing.xl).padding(.vertical, Spacing.m)
                    .background(Capsule(style: .continuous).fill(Palette.HUD.fill))
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 720, height: 600, alignment: .topLeading)
        .background(Palette.canvas)
    }

    private var orbs: some View {
        HStack(spacing: Spacing.l) {
            ForEach([Layout.Orb.small, Layout.Orb.medium, Layout.Orb.large], id: \.self) { side in
                SpectrumOrb(mode: .still, diameter: side, phase: 0)
                SpectrumOrb(mode: .live, diameter: side, showsHalo: true, phase: 1.2)
                SpectrumOrb(mode: .live, diameter: side, level: 0.8, showsHalo: true, phase: 2.4)
                SpectrumOrb(mode: .thinking, diameter: side, showsHalo: true, phase: 0.3)
            }
        }
    }
}

/// The done check in warm white and in success green, side by side on the pill's navy, to
/// choose between them.
struct HUDCheckComparison: View {
    var body: some View {
        ZStack {
            HUDBackdrop()
            HStack(spacing: Spacing.xxxl) {
                check(Palette.HUD.check)
                check(Palette.HUD.success)
            }
        }
        .frame(width: HUDPreview.sceneSize.width, height: HUDPreview.sceneSize.height)
    }

    private func check(_ colour: Color) -> some View {
        ZStack {
            HUDPillBody()
            HUDDrawnCheck(animated: false, color: colour)
        }
        .frame(width: Layout.HUD.height, height: Layout.HUD.height)
    }
}
